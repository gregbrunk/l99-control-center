import AppKit
import L99Skins
import SwiftUI

/// Pick a style for each page of the screen, preview it, and install it (cable, bootloader mode).
struct SkinsView: View {
    let model: AppModel
    private var store: SkinStore { model.skins }
    @State private var showingInstall = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            choices
                .frame(width: 360)
            Divider()
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 660)
        .toolbar { ToolbarItem(placement: .automatic) { CableStatus(connected: model.devices.screen, bootloader: store.inBootloader) } }
        .sheet(isPresented: $showingInstall) { InstallSheet(store: store, isPresented: $showingInstall) }
    }

    // MARK: Choices

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    installedCard
                    HStack {
                        Text("Style for each page").font(.headline)
                        Spacer()
                        Menu("Set all") {
                            ForEach(SkinStyle.allCases, id: \.self) { s in Button(s.displayName) { store.setAll(s) } }
                            Divider()
                            Button("Stock (AULA's original)") { store.setAll(nil) }
                        }
                        .fixedSize()
                    }
                    ForEach(SkinStore.pages, id: \.self) { page in
                        pageRow(page)
                        if page == .home, store.style(.home) != nil { hiddenApps }
                    }
                    Divider()
                    topBarRow
                }
                .padding(16)
            }
            Divider()
            footer.padding(16)
        }
    }

    /// What's on the keyboard now, from the last install made with this app.
    private var installedCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("On the keyboard", systemImage: store.installedPlan == nil ? "keyboard" : "checkmark.seal.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(store.installedPlan == nil ? Color.secondary : .green)
            Text(store.installedSummary).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            if let date = store.installedDate, store.installedPlan != nil {
                Text("Installed \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if store.homeSkinInstalled {
                Text("The Home skin replaces backgrounds. On the keyboard, keep Screen › Background on Default; Customization puts an old background behind the top bar.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func styleMenu(_ selection: SkinStyle?, stockLabel: String, set: @escaping (SkinStyle?) -> Void) -> some View {
        Picker("", selection: Binding(get: { selection }, set: set)) {
            Text(stockLabel).tag(SkinStyle?.none)
            Divider()
            ForEach(SkinStyle.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
        }
        .labelsHidden()
        .frame(width: 190)
    }

    private func pageRow(_ page: SkinSection) -> some View {
        HStack {
            Button {
                store.selected = page
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon(page)).frame(width: 18)
                    Text(page.displayName)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fontWeight(store.selected == page ? .semibold : .regular)
            .foregroundStyle(store.selected == page ? Color.accentColor : .primary)
            styleMenu(store.style(page), stockLabel: "Stock") { store.setStyle($0, for: page); store.selected = page }
        }
    }

    private var hiddenApps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps on Home").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 4) {
                ForEach(HomeApp.allCases, id: \.self) { app in
                    Toggle(app.displayName, isOn: Binding(get: { !store.isHidden(app) }, set: { store.setHidden(app, !$0) }))
                        .toggleStyle(.checkbox)
                        .font(.callout)
                }
            }
            Text("Unticked apps are hidden; the others fill the grid.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 26)
    }

    private var topBarRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "menubar.rectangle").frame(width: 18)
                Text("Top bar")
                Spacer()
                styleMenu(store.style(.topBar), stockLabel: "Match Home") { store.setStyle($0, for: .topBar) }
            }
            Text("One top bar is shared by every restyled page. Stock pages keep their own.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !store.lowContrast.isEmpty, let bar = store.plan.topBarStyle {
                Notice(systemImage: "eye.trianglebadge.exclamationmark", tint: .orange,
                       text: "The \(bar.displayName) top bar is hard to read on " +
                             store.lowContrast.map(\.displayName).formatted(.list(type: .and)) + ". Try a top bar that matches those pages.")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.hasStock {
                StockFileCard(store: store)
            } else {
                Text(statusLine).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Back to stock…") { store.prepareInstall(stock: true); showingInstall = true }
                        .disabled(store.isInstalling)
                    Spacer()
                    Button("Install on keyboard…") { store.prepareInstall(stock: false); showingInstall = true }
                        .buttonStyle(.borderedProminent)
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
        VStack(spacing: 18) {
            // The big preview takes whatever height the thumbnails leave, up to 1.25×.
            GeometryReader { geo in
                let scale = max(0.4, min(1.25, geo.size.height / 480, geo.size.width / 320))
                ScreenPreview(image: store.previews[store.selected], scale: scale, page: store.selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 12) {
                ForEach(SkinStore.pages, id: \.self) { page in
                    Button { store.selected = page } label: {
                        VStack(spacing: 4) {
                            ScreenPreview(image: store.previews[page], scale: 0.3, page: page)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(store.selected == page ? Color.accentColor : .clear, lineWidth: 2))
                            Text(page.displayName).font(.caption2)
                                .foregroundStyle(store.selected == page ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
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
        .clipShape(RoundedRectangle(cornerRadius: scale > 0.5 ? 14 : 6))
        .shadow(color: .black.opacity(0.25), radius: scale > 0.5 ? 12 : 3, y: 2)
        .accessibilityLabel("\(page.displayName) preview")
    }
}

/// Asks once for AULA's stock interface file; every skin is built from it.
private struct StockFileCard: View {
    let store: SkinStore

    var body: some View {
        Card(systemImage: "doc.badge.gearshape", tint: .primary, title: "One-time setup") {
            Text("Skins are built from the screen's original interface file. Choose UartTFT-II_Flash.bin from AULA's reset package; it's checked against the verified copy and kept with the app.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(store.importingStock ? "Checking…" : "Choose UartTFT-II_Flash.bin…") { choose() }
                    .disabled(store.importingStock)
                if store.importingStock { ProgressView().controlSize(.small) }
            }
            if let e = store.stockError { Text(e).font(.caption).foregroundStyle(.red) }
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

    private var stock: Bool {
        switch store.install {
        case .ready(let s), .waitingForPassword(let s), .installing(let s, _, _), .done(let s): s
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(stock ? "Put back the stock screen" : "Install your skin").font(.title2.weight(.semibold))
            Text("This replaces the screen's interface pages (about 4½ minutes). Your keys, lighting and the screen's own program aren't touched.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            step(1, "Build the skin", state: buildState) {
                if case .building = store.install { Text("Rendering every page…").font(.caption).foregroundStyle(.secondary) }
            }
            step(2, "Plug in the cable and start bootloader mode", state: bootloaderState) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold Fn and tap X, 0, 6. The screen goes dark and shows the Bootloader text.").font(.callout)
                    if !store.bootloaderReady {
                        Text(store.screenNormal ? "The screen is connected but not in bootloader mode yet." : "Waiting for the keyboard on the USB cable…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            step(3, "Install", state: installState) { installDetail }

            HStack {
                if case .done = store.install {
                    Text("You can unplug the cable and switch back to the dongle.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isInstalling {
                    Text("Keep the cable in and don't touch the screen.").font(.caption).foregroundStyle(.orange)
                } else if case .done = store.install {
                    Button("Done") { store.cancelInstall(); isPresented = false }.buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { store.cancelInstall(); isPresented = false }
                    Button("Install") { store.startInstall() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!(store.bootloaderReady && isReady))
                }
            }
        }
        .padding(22)
        .frame(width: 520)
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
            Text("macOS asks for your password to let the app reach the screen directly.").font(.callout)
        case .installing(_, let verifying, let percent):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(percent), total: 100)
                Text(verifying ? "Checking what the screen stored… \(percent)%" : "Writing… \(percent)%").font(.caption).foregroundStyle(.secondary)
            }
        case .done:
            Text("Installed, and every check matched. The screen restarts by itself; if it stays dark, switch the keyboard off and on.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Text("If the screen still shows the Bootloader text, it's safe to try again.").font(.caption).foregroundStyle(.secondary)
            }
        default:
            Text("Click Install when step 2 is ticked. macOS will ask for your password.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step<Detail: View>(_ n: Int, _ title: String, state: StepState, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(state == .done ? Color.green : state == .active ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 26, height: 26)
                if state == .done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(state == .active ? .white : .secondary) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(state == .waiting ? .secondary : .primary)
                if state == .active || state == .done || n == 3 { detail() }
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
/// Debug builds: `--render-skins <path> [--install-step]` draws the Skins window offscreen into a PNG and
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
        let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 980, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        let root: AnyView = args.contains("--library")
            ? AnyView(LibraryView(model: model).background(Color(nsColor: .windowBackgroundColor)))
            : AnyView(SkinsView(model: model).background(Color(nsColor: .windowBackgroundColor)))
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
