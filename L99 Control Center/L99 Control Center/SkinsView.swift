import AppKit
import L99Core
import L99Skins
import SwiftUI

/// Pick a style for each page of the screen, preview it, and install it (cable, bootloader mode).
struct SkinsView: View {
    let model: AppModel
    private var store: SkinStore { model.skins }
    @State private var showingInstall = false

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                choices
                    .frame(width: min(460, max(390, geo.size.width * 0.4)))
                Divider()
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showingInstall) { InstallSheet(store: store, isPresented: $showingInstall) }
    }

    // MARK: Choices

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    installedCard
                    HStack {
                        SectionLabel("Style for each page")
                        Spacer()
                        Menu {
                            ForEach(SkinStyle.allCases, id: \.self) { s in Button(s.displayName) { store.setAll(s) } }
                            Divider()
                            Button("Stock (AULA's original)") { store.setAll(nil) }
                        } label: {
                            Label("Set all", systemImage: "wand.and.stars")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.studio)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    VStack(spacing: 8) {
                        ForEach(SkinStore.pages, id: \.self) { page in
                            pageRow(page)
                            if page == .home, store.style(.home) != nil { hiddenApps }
                        }
                    }
                    topBarRow
                }
                .padding(24)
            }
            Divider()
            footer.padding(20)
        }
    }

    /// What's on the keyboard now, from the last install made with this app.
    private var installedCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                StyleSwatch(style: store.installedPlan?.topBarStyle, size: 44)
                Image(systemName: store.installedPlan == nil ? "keyboard" : "checkmark")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white).shadow(radius: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ON THE KEYBOARD").font(.system(size: 11, weight: .semibold)).kerning(0.8)
                    .foregroundStyle(store.installedPlan == nil ? Color.secondary : .green)
                Text(store.installedSummary).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if let date = store.installedDate, store.installedPlan != nil {
                    Text("Installed \(date.formatted(date: .abbreviated, time: .shortened))").font(.l99Note).foregroundStyle(.secondary)
                }
                if store.homeSkinInstalled {
                    Text("The Home skin replaces backgrounds. On the keyboard, keep Screen › Background on Default.")
                        .font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(padding: 16)
    }

    /// A capsule menu showing the chosen style's swatch and name.
    private func styleMenu(_ selection: SkinStyle?, stockLabel: String, set: @escaping (SkinStyle?) -> Void) -> some View {
        Menu {
            Button { set(nil) } label: { Text(stockLabel) }
            Divider()
            ForEach(SkinStyle.allCases, id: \.self) { s in
                Button { set(s) } label: {
                    if s == selection { Label(s.displayName, systemImage: "checkmark") } else { Text(s.displayName) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                StyleSwatch(style: selection, size: 16)
                Text(selection?.displayName ?? stockLabel).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Studio.ink)
            .padding(.horizontal, 12)
            .frame(width: 172, height: 34)
            .background(Studio.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Studio.stroke))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func pageRow(_ page: SkinSection) -> some View {
        let selected = store.selected == page
        return HStack(spacing: 12) {
            Button {
                withAnimation(Studio.snap) { store.selected = page }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon(page))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? Studio.accent : Color.secondary)
                        .frame(width: 32, height: 32)
                        .background(selected ? Studio.accent.opacity(0.14) : Studio.secondaryFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(page.displayName)
                        .font(.system(size: 14.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Studio.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            styleMenu(store.style(page), stockLabel: "Stock") { store.setStyle($0, for: page); store.selected = page }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Studio.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Studio.accent.opacity(0.35) : .clear))
    }

    /// The Home grid in miniature: tap an app to show or hide it on the keyboard's Home page.
    private var hiddenApps: some View {
        let shown = HomeApp.allCases.filter { !store.isHidden($0) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps on Home").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(shown) of \(HomeApp.allCases.count) shown").font(.l99Note).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(HomeApp.allCases, id: \.self) { app in HomeAppTile(app: app, shown: !store.isHidden(app)) { store.setHidden(app, !store.isHidden(app)) } }
            }
            Text("Tap an app to hide it. The ones left fill the grid.").font(.l99Note).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Studio.secondaryFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var topBarRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Studio.secondaryFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Top bar").font(.system(size: 14.5, weight: .medium))
                    Text("Shared by every restyled page").font(.l99Note).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                styleMenu(store.style(.topBar), stockLabel: "Match Home") { store.setStyle($0, for: .topBar) }
            }
            .padding(.horizontal, 10)
            if !store.lowContrast.isEmpty, let bar = store.plan.topBarStyle {
                Notice(systemImage: "eye.trianglebadge.exclamationmark", tint: .orange,
                       text: "The \(bar.displayName) top bar is hard to read on " +
                             store.lowContrast.map(\.displayName).formatted(.list(type: .and)) + ". Try a top bar that matches those pages.",
                       large: true)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.hasStock {
                StockFileCard(store: store)
            } else {
                HStack(spacing: 8) {
                    Circle().fill(store.hasChanges && !store.isStockPlan ? Studio.accent : .green).frame(width: 7, height: 7)
                    Text(statusLine).font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button("Back to stock…") { store.prepareInstall(stock: true); showingInstall = true }
                        .controlSize(.large)
                        .disabled(store.isInstalling)
                    Button { store.prepareInstall(stock: false); showingInstall = true } label: {
                        Label("Install skin", systemImage: "arrow.down.to.line.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.studioPrimary)
                    .controlSize(.large)
                    .disabled(store.isStockPlan || store.isInstalling)
                }
            }
        }
    }

    private var statusLine: String {
        if store.isStockPlan { return "Every page is stock. Pick a style for at least one page to install a skin." }
        return store.hasChanges ? "These choices aren't on the keyboard yet." : "This is what's on the keyboard."
    }

    private func icon(_ page: SkinSection) -> String {
        switch page {
        case .home: "house"
        case .play: "play.circle"
        case .data: "chart.xyaxis.line"
        case .numpad: "number.square"
        case .calculator: "plus.forwardslash.minus"
        case .topBar: "menubar.rectangle"
        }
    }

    // MARK: Preview

    private var previewPane: some View {
        GeometryReader { geo in
            // Thumbnails share the width; the big preview takes the height they leave, up to 1.6×.
            let thumb = min(0.36, max(0.2, (geo.size.width - 48 - 4 * 14) / 5 / 320))
            let bigHeight = geo.size.height - 48 - 480 * thumb - 22 - 28
            let scale = max(0.5, min(1.6, bigHeight / 480, (geo.size.width - 48) / 320))
            VStack(spacing: 28) {
                ScreenPreview(image: store.previews[store.selected], scale: scale, page: store.selected)
                    .id(store.selected)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 14) {
                    ForEach(SkinStore.pages, id: \.self) { page in
                        let on = store.selected == page
                        Button { withAnimation(Studio.snap) { store.selected = page } } label: {
                            VStack(spacing: 6) {
                                ScreenPreview(image: store.previews[page], scale: thumb, page: page)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Studio.accent : .clear, lineWidth: 2.5))
                                    .scaleEffect(on ? 1.04 : 1)
                                Text(page.displayName).font(.system(size: 12, weight: on ? .semibold : .medium))
                                    .foregroundStyle(on ? Studio.accent : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .hoverLift(1.03)
                    }
                }
                .fixedSize()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Studio.motion, value: store.selected)
        }
        .background(Studio.canvas.opacity(0.55))
    }
}

/// One app in the miniature Home grid: solid with a tick when shown, faded and dashed when hidden.
private struct HomeAppTile: View {
    let app: HomeApp
    let shown: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button { withAnimation(Studio.snap) { toggle() } } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(shown ? Studio.accent : Color.secondary)
                    .frame(height: 22)
                Text(app.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(shown ? Studio.ink : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(shown ? Studio.card : Color.clear, in: shape)
            .overlay {
                if shown { shape.strokeBorder(hovering ? Studio.accent.opacity(0.5) : Studio.stroke) }
                else { shape.strokeBorder(Color.secondary.opacity(hovering ? 0.6 : 0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: shown ? "checkmark.circle.fill" : "eye.slash")
                    .font(.system(size: shown ? 11 : 9, weight: .semibold))
                    .foregroundStyle(shown ? Studio.accent : Color.secondary)
                    .padding(5)
            }
            .shadow(color: .black.opacity(shown ? 0.04 : 0), radius: 3, y: 1)
            .opacity(shown ? 1 : 0.7)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(shown ? "Shown on Home. Click to hide." : "Hidden. Click to show on Home.")
        .accessibilityLabel(app.displayName)
        .accessibilityValue(shown ? "Shown" : "Hidden")
    }

    private var icon: String {
        switch app {
        case .settings: "gearshape"
        case .screen: "display"
        case .colour: "lightbulb"
        case .gifs: "film"
        case .photos: "photo"
        case .numpad: "number.square"
        case .calculator: "plus.forwardslash.minus"
        case .touchpad: "hand.point.up.left"
        }
    }
}

/// A 320×480 screen image at a scale, or a placeholder for a stock page.
private struct ScreenPreview: View {
    let image: CGImage?
    let scale: CGFloat
    let page: SkinSection

    var body: some View {
        let w = 320 * scale, h = 480 * scale
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            } else {
                ZStack {
                    Color.black
                    if scale > 0.5 {
                        VStack(spacing: 6) {
                            Text("Stock").font(.title3.weight(.semibold))
                            Text("\(page.displayName) keeps AULA's original look.").font(.callout).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white.opacity(0.7)).padding()
                    } else {
                        Text("Stock").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: scale > 0.5 ? 18 * scale : 8, style: .continuous))
        .shadow(color: .black.opacity(scale > 0.5 ? 0.30 : 0.18), radius: scale > 0.5 ? 26 : 5, y: scale > 0.5 ? 14 : 3)
        .accessibilityLabel("\(page.displayName) preview")
    }
}

/// Asks once for AULA's stock interface file; every skin is built from it.
private struct StockFileCard: View {
    let store: SkinStore

    var body: some View {
        Card(systemImage: "doc.badge.gearshape", tint: .primary, title: "One-time setup") {
            Text("Skins are built from the screen's original interface file. Choose UartTFT-II_Flash.bin from AULA's reset package; it's checked against the verified copy and kept with the app.")
                .font(.l99Body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(store.importingStock ? "Checking…" : "Choose UartTFT-II_Flash.bin…") { choose() }
                    .disabled(store.importingStock)
                if store.importingStock { ProgressView().controlSize(.small) }
            }
            if let e = store.stockError { Text(e).font(.l99Note).foregroundStyle(.red) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose UartTFT-II_Flash.bin"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { store.importStock(from: url) }
    }
}

/// The guided install: build, cable and bootloader mode, administrator approval, progress.
private struct InstallSheet: View {
    let store: SkinStore
    @Binding var isPresented: Bool

    private var stock: Bool { store.installIsStock }

    /// Which of the screen's pictures the install carries over.
    private var keptLine: String {
        let order: [ScreenProtocol.Slot] = [.photo, .gif, .background]
        let kept = order.compactMap { slot in store.keptNames[slot].map { "\(slot.displayName.lowercased()) “\($0)”" } }
        let factory = order.filter { $0 != .background && store.keptNames[$0] == nil }.map { $0.displayName.lowercased() }
        var parts: [String] = []
        if !kept.isEmpty { parts.append("Keeps your " + kept.formatted(.list(type: .and)) + ".") }
        if !factory.isEmpty { parts.append("The " + factory.formatted(.list(type: .and)) + " will be the factory one.") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(stock ? "Put back the stock screen" : "Install your skin").font(.system(size: 22, weight: .semibold))
            Text("This replaces the screen's interface pages (about 4½ minutes). Your keys, lighting and the screen's own program aren't touched.")
                .font(.l99Body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            step(1, stock ? "Prepare the stock file" : "Build the skin", state: buildState) {
                VStack(alignment: .leading, spacing: 2) {
                    if case .building = store.install {
                        Text(stock ? "Adding your pictures…" : "Rendering every page…").font(.l99Note).foregroundStyle(.secondary)
                    }
                    Text(keptLine).font(.l99Note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            step(2, "Plug in the cable and start bootloader mode", state: bootloaderState) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold Fn and tap X, 0, 6. The screen goes dark and shows the Bootloader text.").font(.l99Body)
                    if !store.bootloaderReady {
                        Text(store.screenNormal ? "The screen is connected but not in bootloader mode yet." : "Waiting for the keyboard on the USB cable…")
                            .font(.l99Note).foregroundStyle(.secondary)
                    }
                }
            }
            step(3, "Install", state: installState) { installDetail }

            HStack {
                if case .done = store.install {
                    Text("You can unplug the cable and switch back to the dongle.").font(.l99Note).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isInstalling {
                    Text("Keep the cable in and don't touch the screen.").font(.l99Note).foregroundStyle(.orange)
                } else if case .done = store.install {
                    Button("Done") { store.cancelInstall(); isPresented = false }.buttonStyle(.studioPrimary).controlSize(.large)
                } else {
                    Button("Cancel") { store.cancelInstall(); isPresented = false }
                        .controlSize(.large)
                    Button("Install") { store.startInstall() }
                        .controlSize(.large)
                        .buttonStyle(.studioPrimary)
                        .disabled(!(store.bootloaderReady && isReady))
                }
            }
        }
        .padding(28)
        .frame(width: 580)
        .interactiveDismissDisabled(store.isInstalling)
    }

    private var isReady: Bool { if case .ready = store.install { true } else { false } }

    enum StepState { case waiting, active, done }

    private var buildState: StepState {
        switch store.install {
        case .idle: .waiting
        case .building: .active
        default: .done
        }
    }
    private var bootloaderState: StepState {
        switch store.install {
        case .ready: store.bootloaderReady ? .done : .active
        case .waitingForPassword, .installing, .done: .done
        default: .waiting
        }
    }
    private var installState: StepState {
        switch store.install {
        case .ready: store.bootloaderReady ? .active : .waiting
        case .waitingForPassword, .installing: .active
        case .done: .done
        default: .waiting
        }
    }

    @ViewBuilder private var installDetail: some View {
        switch store.install {
        case .waitingForPassword:
            Text("macOS asks for your password to let the app reach the screen directly.").font(.l99Body)
        case .installing(_, let verifying, let percent):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(percent), total: 100)
                Text(verifying ? "Checking what the screen stored… \(percent)%" : "Writing… \(percent)%").font(.l99Note).foregroundStyle(.secondary)
            }
        case .done:
            Text("Installed, and every check matched. The screen restarts by itself; if it stays dark, switch the keyboard off and on.")
                .font(.l99Body).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.l99Body).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Text("If the screen still shows the Bootloader text, it's safe to try again.").font(.l99Note).foregroundStyle(.secondary)
            }
        default:
            Text("Click Install when step 2 is ticked. macOS will ask for your password.").font(.l99Note).foregroundStyle(.secondary)
        }
    }

    private func step<Detail: View>(_ n: Int, _ title: String, state: StepState, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(state == .done ? Color.green : state == .active ? Studio.accent : Color.secondary.opacity(0.25))
                    .frame(width: 30, height: 30)
                if state == .done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(state == .active ? .white : .secondary) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.l99Headline).foregroundStyle(state == .waiting ? .secondary : .primary)
                if state == .active || state == .done || n == 3 { detail() }
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
/// Debug builds: `--render-skins <path> [--tab library] [--select data]` draws the main window offscreen into a PNG and
/// quits, so the layout can be checked without opening the menu bar.
enum DebugSnapshot {
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-skins"), i + 1 < args.count else { return }
        let path = args[i + 1]
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel()
        if let j = args.firstIndex(of: "--select"), j + 1 < args.count, let page = SkinSection(rawValue: args[j + 1]) { model.skins.selected = page }
        if let j = args.firstIndex(of: "--tab"), j + 1 < args.count, let tab = AppTab(rawValue: args[j + 1]) { model.tab = tab }
        var size = CGSize(width: 1260, height: 830)
        if let j = args.firstIndex(of: "--size"), j + 1 < args.count {
            let wh = args[j + 1].split(separator: "x").compactMap { Double($0) }
            if wh.count == 2 { size = CGSize(width: wh[0], height: wh[1]) }
        }
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -3000, y: 0), size: size), styleMask: [.titled], backing: .buffered, defer: false)
        let root = MainWindow(model: model)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
        app.run()
    }
}
#endif
