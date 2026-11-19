import AppKit
import Foundation
import L99Core
import L99Link
import L99Skins
import Observation

/// The Skins window's state: the chosen style per page, previews, the stock file, and the install.
@Observable
final class SkinStore {
    // MARK: Choices

    var plan: SkinPlan { didSet { save(plan, "skinPlan"); refreshPreviews() } }
    /// The plan on the keyboard now (nil = stock, or unknown before the first install from the app).
    private(set) var installedPlan: SkinPlan?
    /// When the skin on the keyboard was installed from this app.
    private(set) var installedDate: Date?
    /// Something on the screen now that an install carries over, so it isn't replaced by factory content.
    struct KeptItem: Sendable {
        let slot: ScreenProtocol.Slot, id: UUID, name: String, payload: [UInt8]
    }
    /// Supplies what's on the screen now. The background is asked for only when Home stays stock
    /// (a Home skin fills the background slot with its own picture).
    @ObservationIgnored var contentToKeep: ((_ includeBackground: Bool) -> [KeptItem])?
    /// What the prepared install keeps, by slot (names for the sheet, ids for the Library afterwards).
    /// Whether the install being prepared or run is Back to stock.
    private(set) var installIsStock = false
    private(set) var keptNames: [ScreenProtocol.Slot: String] = [:]
    @ObservationIgnored private var keptIDs: [ScreenProtocol.Slot: UUID] = [:]
    /// Called after any install (a skin or stock) with what it kept: it rewrites the screen's picture memory too.
    @ObservationIgnored var onInstalled: (([ScreenProtocol.Slot: UUID]) -> Void)?
    /// A skinned Home draws its own full-screen picture, so the background slot belongs to the skin.
    var homeSkinInstalled: Bool { installedPlan?.styles[.home] != nil }

    /// One line on what's on the keyboard now.
    var installedSummary: String {
        guard let p = installedPlan, !p.pages.isEmpty else { return "Stock: AULA's original look" }
        let styles = Set(p.pages.compactMap { p.styles[$0] })
        if p.pages.count == Self.pages.count, styles.count == 1, let s = styles.first { return "\(s.displayName) on every page" }
        let parts = p.pages.compactMap { page in p.styles[page].map { "\(page.displayName): \($0.displayName)" } }
        return parts.joined(separator: " · ") + (p.pages.count < Self.pages.count ? " · others stock" : "")
    }
    var selected: SkinSection = .home

    static let pages: [SkinSection] = [.home, .play, .data, .numpad, .calculator]
    /// Below this WCAG contrast ratio the top bar reads poorly over a page.
    static let minimumContrast = 3.0

    // MARK: Previews (rendered off the main thread, one at a time: the renderer isn't thread-safe)

    private(set) var previews: [SkinSection: CGImage] = [:]
    private(set) var lowContrast: [SkinSection] = []
    private let renderQueue = DispatchQueue(label: "L99 skin renderer", qos: .userInitiated)
    private var renderGeneration = 0

    // MARK: Files

    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("L99 Control Center/Skins", isDirectory: true)
    let stockURL = folder.appendingPathComponent("UartTFT-II_Flash.bin")
    let builtURL = folder.appendingPathComponent("Skin.bin")
    let statusURL = folder.appendingPathComponent("install-status.txt")
    private(set) var hasStock = false
    private(set) var importingStock = false
    private(set) var stockError: String?

    // MARK: Install

    enum Install: Equatable {
        case idle
        case building
        /// The file is ready; waiting for the screen's bootloader (cable, Fn+X,0,6) and the go-ahead.
        case ready(stock: Bool)
        case waitingForPassword(stock: Bool)
        case installing(stock: Bool, verifying: Bool, percent: Int)
        case done(stock: Bool)
        case failed(String)
    }
    private(set) var install: Install = .idle
    private(set) var bootloaderReady = false
    /// Bootloader mode, as seen while an install is under way (only polled then).
    var inBootloader: Bool {
        switch install {
        case .ready, .waitingForPassword, .installing: bootloaderReady
        default: false
        }
    }
    private(set) var screenNormal = false
    private var pollTimer: Timer?
    private var installProcess: Process?

    init() {
        plan = Self.load("skinPlan") ?? SkinPlan(styles: [:])
        installedPlan = Self.load("installedSkinPlan")
        installedDate = UserDefaults.standard.object(forKey: "installedSkinDate") as? Date
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        hasStock = FileManager.default.fileExists(atPath: stockURL.path)
        refreshPreviews()
    }

    // MARK: Plan helpers

    func style(_ s: SkinSection) -> SkinStyle? { plan.styles[s] }
    /// Follows the app's Units setting; the Data page prints °F or °C.
    var fahrenheit: Bool {
        get { plan.usesFahrenheit }
        set { if newValue != plan.usesFahrenheit { plan.fahrenheit = newValue ? true : nil } }
    }
    func setStyle(_ style: SkinStyle?, for s: SkinSection) { plan.styles[s] = style }
    func setAll(_ style: SkinStyle?) {
        var p = plan
        for s in Self.pages { p.styles[s] = style }
        p.styles[.topBar] = nil
        plan = p
    }
    func isHidden(_ app: HomeApp) -> Bool { plan.hiddenApps.contains(app) }
    func setHidden(_ app: HomeApp, _ hidden: Bool) {
        if hidden { plan.hiddenApps.insert(app) } else { plan.hiddenApps.remove(app) }
    }
    var hasChanges: Bool { plan != (installedPlan ?? SkinPlan()) }
    var isStockPlan: Bool { plan.pages.isEmpty }

    // MARK: Previews

    func refreshPreviews() {
        renderGeneration += 1
        let generation = renderGeneration, plan = plan
        renderQueue.async { [weak self] in
            var images: [SkinSection: CGImage] = [:]
            var low: [SkinSection] = []
            let bar = plan.topBarStyle
            for page in Self.pages {
                guard let style = plan.styles[page] else { continue }
                images[page] = SkinPreview.render(page, style: style, topBar: bar,
                                                  hidden: page == .home ? Set(plan.hiddenApps.map(\.displayName)) : [],
                                                  fahrenheit: plan.usesFahrenheit)
                if let bar, SkinPreview.topBarContrast(page: style, topBar: bar) < Self.minimumContrast { low.append(page) }
            }
            DispatchQueue.main.async {
                guard let self, generation == self.renderGeneration else { return }
                self.previews = images
                self.lowContrast = low
            }
        }
    }

    // MARK: Stock file

    /// Checks AULA's UartTFT-II_Flash.bin (the verified factory copy) and keeps a copy for building skins.
    func importStock(from url: URL) {
        importingStock = true; stockError = nil
        let dest = stockURL
        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error> = Result {
                _ = try InterfaceFile(stockFile: url.path)     // checks the SHA-256 of the verified stock file
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: url, to: dest)
            }
            await MainActor.run {
                self.importingStock = false
                switch result {
                case .success: self.hasStock = true
                case .failure(let e):
                    self.stockError = e is InterfaceFile.Failure
                        ? "That isn't the verified stock UartTFT-II_Flash.bin from AULA's reset package."
                        : e.localizedDescription
                }
            }
        }
    }

    // MARK: Install

    /// Builds the skin (or picks the stock file), then waits for the bootloader.
    func prepareInstall(stock: Bool) {
        guard hasStock else { return }
        installIsStock = stock
        install = .building
        let keep = contentToKeep?(stock || plan.styles[.home] == nil) ?? []
        keptNames = Dictionary(keep.map { ($0.slot, $0.name) }, uniquingKeysWith: { a, _ in a })
        keptIDs = Dictionary(keep.map { ($0.slot, $0.id) }, uniquingKeysWith: { a, _ in a })
        let plan = plan, stockURL = stockURL, out = builtURL
        renderQueue.async { [weak self] in
            let result: Result<Void, Error> = Result {
                let bytes = [UInt8](try Data(contentsOf: stockURL))
                var file = stock ? try InterfaceFile(stockBytes: bytes) : try SkinBuilder.build(plan, stockBytes: bytes).file
                for k in keep { try file.setSlotContent(k.slot, payload: k.payload, name: k.name) }
                _ = try file.write(to: out.path)
            }
            DispatchQueue.main.async {
                guard let self, self.install == .building else { return }
                switch result {
                case .success: self.install = .ready(stock: stock); self.startPolling()
                case .failure(let e): self.install = .failed("The skin couldn't be built: \(e.localizedDescription)")
                }
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func poll() {
        let names = BootloaderPort.productNames()
        bootloaderReady = names == ["USB_VCOM"]
        screenNormal = names.contains("Generic CDC")
        switch install {
        case .waitingForPassword(let stock), .installing(let stock, _, _):
            guard let line = try? String(contentsOf: statusURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { return }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "writing", "verifying":
                install = .installing(stock: stock, verifying: parts[0] == "verifying", percent: Int(parts.count > 1 ? parts[1] : "0") ?? 0)
            case "done":
                install = .done(stock: stock)
                installedPlan = stock ? nil : plan
                save(installedPlan, "installedSkinPlan")
                installedDate = Date()
                UserDefaults.standard.set(installedDate, forKey: "installedSkinDate")
                onInstalled?(keptIDs)
                stopPolling()
            case "error":
                install = .failed(parts.count > 1 ? parts[1] : "The install stopped.")
                stopPolling()
            default: break
            }
        default: break
        }
    }

    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    /// Starts the installer with administrator rights (macOS asks for the password in its own dialog).
    func startInstall() {
        guard case .ready(let stock) = install, bootloaderReady else { return }
        try? FileManager.default.removeItem(at: statusURL)
        let file = builtURL   // stock too: the stock file plus the photo and GIF it keeps
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let exe = Bundle.main.executableURL!.path
        let command = "\(q(exe)) \(InterfaceInstaller.flag) \(q(file.path)) --status \(q(statusURL.path)) >/dev/null 2>&1"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let prompt = "L99 Control Center needs your permission to install on the keyboard's screen."
        let script = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.poll()
                // osascript fails without a status line when the password prompt was cancelled.
                if case .waitingForPassword = self.install, status != 0 {
                    self.install = .ready(stock: stock)
                } else if case .installing = self.install, status != 0 {
                    self.install = .failed("The installer stopped unexpectedly. If the screen still shows the Bootloader text, try again.")
                    self.stopPolling()
                }
            }
        }
        install = .waitingForPassword(stock: stock)
        do { try p.run(); installProcess = p } catch { install = .failed("Couldn't start the installer: \(error.localizedDescription)") }
    }

    func cancelInstall() {
        switch install {
        case .waitingForPassword, .installing: return       // can't be stopped safely once started
        default: stopPolling(); install = .idle
        }
    }

    var isInstalling: Bool {
        switch install {
        case .waitingForPassword, .installing: true
        default: false
        }
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
