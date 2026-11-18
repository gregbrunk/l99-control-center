import AppKit
import Foundation
import L99Core
import L99Link
import Observation

/// Live data for the keyboard's screen: clock, CPU/GPU load, weather and the music bars,
/// plus battery. Over the 2.4 GHz dongle when the keyboard answers there, else over the cable.
/// Only volatile commands: the clock/stats and music packets, and read-only dongle queries.
@Observable
final class KeyboardLink {
    private(set) var status = LiveStatus()
    let settings: LiveSettings
    let weather: WeatherModel

    var batteryPercent: Int? { status.battery }
    var lastClockSync: Date? { status.lastSync }
    var lastError: String? { status.error }

    @ObservationIgnored private let engine: LiveEngine
    @ObservationIgnored private weak var devices: DeviceMonitor?
    @ObservationIgnored private weak var transfer: ScreenTransferController?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var clockRequests = 0

    init(devices: DeviceMonitor, transfer: ScreenTransferController, settings: LiveSettings, weather: WeatherModel) {
        self.devices = devices
        self.transfer = transfer
        self.settings = settings
        self.weather = weather
        engine = LiveEngine()
        let link = WeakLink()
        engine.onStatus = { status in
            Task { @MainActor in link.value?.status = status }
        }
        settings.onChange = { [weak self] in self?.push() }
        weather.onChange = { [weak self] in self?.push() }
        weather.setEnabled(settings.weather)

        // Picks up cable/upload changes; everything else pushes on its own.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensAsleep = true; self?.push() }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensAsleep = false; self?.syncClockNow(); self?.weather.refresh() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncClockNow(); self?.weather.refresh() }
            },
        ]
        link.value = self
        push()
        engine.start()
    }

    /// Called whenever devices come or go.
    func connectionChanged() {
        push()
        // Give a freshly plugged-in device a moment to finish enumerating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.syncClockNow() }
    }

    func syncClockNow() {
        clockRequests += 1
        push()
    }

    private func push() {
        weather.setEnabled(settings.weather)
        var c = LiveConfig()
        c.dongleAttached = devices?.dongle ?? false
        c.cableAttached = devices?.wiredKeyboard ?? false
        c.cableBusy = transfer?.isBusy ?? false
        c.paused = screensAsleep
        c.clock = settings.clock
        c.load = settings.load
        c.weather = settings.weather ? weather.snapshot : nil
        c.music = settings.music
        c.sensitivity = settings.sensitivity
        c.foreMode = UInt8(clamping: settings.foreMode)
        c.backMode = UInt8(clamping: settings.backMode)
        c.clockRequests = clockRequests
        engine.config.set(c)
    }
}

/// Lets the engine's thread reach the link without keeping it alive.
nonisolated final class WeakLink: @unchecked Sendable {
    weak var value: KeyboardLink?
}

/// What the main thread asks the engine to do.
nonisolated struct LiveConfig: Sendable, Equatable {
    var dongleAttached = false
    var cableAttached = false
    var cableBusy = false
    var paused = false
    var clock = true
    var load = true
    var weather: WeatherModel.Snapshot?
    var music = false
    var sensitivity = 0.5
    var foreMode: UInt8 = 2
    var backMode: UInt8 = 0
    /// Goes up by one for each "sync the clock now".
    var clockRequests = 0
}

/// What the engine reports back.
nonisolated struct LiveStatus: Sendable, Equatable {
    enum Route: Sendable { case none, dongle, cable }
    var route = Route.none
    var asleep = false
    var battery: Int?
    var cpu: Int?
    var gpu: Int?
    var lastSync: Date?
    var error: String?
    var listening = false
    var musicPlaying = false
    var levels: [Double] = []
    var audioProblem: String?
}

/// Lock-protected value shared between threads.
nonisolated final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ v: Value) { lock.withLock { value = v } }
}

/// Runs on its own thread. Owns the dongle and cable connections, so nothing else touches them.
nonisolated final class LiveEngine: @unchecked Sendable {
    let config = Locked(LiveConfig())
    var onStatus: (@Sendable (LiveStatus) -> Void)?

    private var thread: Thread?
    private var status = LiveStatus()
    private var lastPosted = LiveStatus()
    private var lastPostTime = Date.distantPast

    private var dongle: Dongle?
    private var wired: WiredKeyboard?
    private var dongleReply = Date.distantPast        // last time the keyboard answered over the dongle
    private var dongleProbe = Date.distantPast
    private var lastBattery = Date.distantPast
    private var lastStats = Date.distantPast
    private var lastCableMusic = Date.distantPast
    private var handledClockRequests = -1

    private let stats = SystemStats()
    private let tap = SystemAudioTap()
    private var analyzer: MusicAnalyzer?
    private var lastSound = Date.distantPast
    private var lastMusicFrame = Date.distantPast
    private var musicWasSent = false

    func start() {
        let t = Thread { [self] in run() }
        t.name = "L99 live data"
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
    }

    private func run() {
        while true {
            let c = config.get()
            autoreleasepool { step(c) }
            // About 60 music frames a second while music plays, otherwise a relaxed 4 checks a second.
            let interval = status.musicPlaying ? 1.0 / 60 : 0.25
            let wait = lastMusicFrame.addingTimeInterval(interval).timeIntervalSinceNow
            Thread.sleep(forTimeInterval: max(0.002, min(interval, wait)))
        }
    }

    private func step(_ c: LiveConfig) {
        manageTap(c)
        if !c.dongleAttached { dongle = nil; dongleReply = .distantPast; status.battery = nil }
        if !c.cableAttached { wired = nil }

        let dongleAwake = Date().timeIntervalSince(dongleReply) < 20
        let route: LiveStatus.Route =
            c.dongleAttached && (dongleAwake || !c.cableAttached) ? .dongle : c.cableAttached ? .cable : .none
        status.route = route
        status.asleep = route == .dongle && !dongleAwake && dongleProbe != .distantPast

        if c.paused || route == .none {
            status.musicPlaying = false
            post()
            return
        }
        do {
            try music(c, route: route)
            // Any clock/stats or battery packet that arrives while music frames stream makes the keyboard
            // drop out of its music lighting for an instant: the top key row blinks green (seen on video,
            // once per stats packet). The Play page doesn't show stats anyway, so hold them until the music stops.
            if !status.musicPlaying {
                try battery(c)
                try statsAndClock(c, route: route)
            }
            status.error = nil
        } catch {
            // A device went away or refused: drop it and reopen on the next step.
            dongle = nil
            wired = nil
            status.error = error.localizedDescription
        }
        post()
    }

    // MARK: Devices

    private func openDongle() throws -> Dongle {
        if let dongle { return dongle }
        let d = try Dongle()
        _ = try d.transact(DongleProtocol.sessionInit, timeout: 0.3)     // read-only, as AULA's driver does first
        dongle = d
        return d
    }

    private func openWired() throws -> WiredKeyboard {
        if let wired { return wired }
        let w = try WiredKeyboard()
        wired = w
        return w
    }

    /// Sends a dongle packet and waits briefly for the keyboard. While it's asleep, tries only every 10 s.
    private func dongleTransact(_ frame: [UInt8]) throws -> [UInt8]? {
        let awake = Date().timeIntervalSince(dongleReply) < 20
        if !awake && Date().timeIntervalSince(dongleProbe) < 10 { return nil }
        dongleProbe = Date()
        let reply = try openDongle().transact(frame, timeout: 0.3)
        if reply != nil { dongleReply = Date() }
        return reply
    }

    // MARK: Battery, clock and stats

    private func battery(_ c: LiveConfig) throws {
        guard c.dongleAttached, Date().timeIntervalSince(lastBattery) > 300 || status.battery == nil else { return }
        guard Date().timeIntervalSince(dongleProbe) > 2 || status.battery == nil else { return }
        if let reply = try dongleTransact(DongleProtocol.batteryQuery), (0...100).contains(Int(reply[3])) {
            status.battery = Int(reply[3])
            lastBattery = Date()
        }
    }

    private func statsAndClock(_ c: LiveConfig, route: LiveStatus.Route) throws {
        let forced = c.clockRequests != handledClockRequests
        let sendsStats = c.load || c.weather != nil
        // CPU/GPU every second; weather alone every 30 s; the clock alone every 6 hours.
        let period: TimeInterval = c.load ? 1 : sendsStats ? 30 : 6 * 3600
        if !c.load {
            status.cpu = nil
            status.gpu = nil
        }
        guard sendsStats || c.clock else { return }
        guard forced || Date().timeIntervalSince(lastStats) >= period else { return }
        if c.load {
            // Sampled only when a packet goes out: about once a second.
            status.cpu = stats.cpuPercent() ?? status.cpu
            status.gpu = stats.gpuPercent() ?? status.gpu
        }

        var r = Realtime(date: Date())
        if c.load {
            r.cpuLoad = status.cpu ?? 0
            r.gpuLoad = status.gpu ?? 0
        }
        if let w = c.weather {
            r.airTemp = min(99, max(-99, w.temperature))
            r.dayHigh = min(99, max(-99, w.high))
            r.nightLow = min(99, max(-99, w.low))
            r.humidity = min(100, max(0, w.humidity))
            r.condition = min(5, max(0, w.condition))
        }
        var sent = false
        switch route {
        case .dongle:
            // plus3 carries clock, stats and weather; without stats use the time-only packet so nothing is blanked.
            let frame = try DongleProtocol.clock(r, layout: sendsStats ? .plus3 : .prior)
            sent = try dongleTransact(frame) != nil
        case .cable:
            guard !c.cableBusy else { return }       // never while the screen is taking an upload
            try openWired().send(KeyboardProtocol.realtime(r))
            sent = true
        case .none:
            return
        }
        lastStats = Date()
        if sent {
            handledClockRequests = c.clockRequests
            status.lastSync = Date()
        }
    }

    // MARK: Music

    private func manageTap(_ c: LiveConfig) {
        let want = c.music && !c.paused
        if want && !tap.isRunning {
            do {
                try tap.start()
                analyzer = MusicAnalyzer(bandCount: DongleProtocol.musicBands, sampleRate: tap.sampleRate)
                status.audioProblem = nil
            } catch {
                status.audioProblem = error.localizedDescription
            }
        } else if !want && tap.isRunning {
            tap.stop()
            analyzer = nil
            status.levels = []
            status.musicPlaying = false
        }
        status.listening = tap.isRunning
    }

    private func music(_ c: LiveConfig, route: LiveStatus.Route) throws {
        guard tap.isRunning, let analyzer else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMusicFrame) >= 1.0 / 62 else { return }
        lastMusicFrame = now
        analyzer.sensitivity = c.sensitivity
        let levels = analyzer.process(tap.ring.latest(analyzer.fftSize))
        if analyzer.lastRMS >= MusicAnalyzer.silenceRMS { lastSound = now }
        status.levels = levels

        // Stop sending a moment after the sound stops, so the keys go back to their own lighting.
        let playing = now.timeIntervalSince(lastSound) < 1.5
        status.musicPlaying = playing
        guard playing || levels.contains(where: { $0 > 0 }) else {
            musicWasSent = false
            return
        }
        switch route {
        case .dongle:
            // Only stream while the keyboard is awake; otherwise one probe a second.
            let awake = now.timeIntervalSince(dongleReply) < 5
            guard awake || now.timeIntervalSince(dongleProbe) > 1 else { return }
            if !awake { dongleProbe = now }
            if try openDongle().send(DongleProtocol.music(levels: levels, foreMode: c.foreMode, backMode: c.backMode)) {
                dongleReply = now
            }
            musicWasSent = true
        case .cable:
            // The cable needs four acknowledged reports per frame, so about 4 frames a second at most.
            guard !c.cableBusy, now.timeIntervalSince(lastCableMusic) >= 0.25 else { return }
            lastCableMusic = now
            try openWired().send(KeyboardProtocol.music(levels: MusicAnalyzer.resample(levels, to: 18), layout: .axira,
                                                               foreMode: c.foreMode, backMode: c.backMode))
            musicWasSent = true
        case .none:
            break
        }
    }

    // MARK: Reporting

    private func post() {
        let changed = status != lastPosted
        // Bars change every frame; the UI only needs about 15 updates a second.
        guard changed, Date().timeIntervalSince(lastPostTime) >= 1.0 / 15 || status.levels == lastPosted.levels else { return }
        lastPosted = status
        lastPostTime = Date()
        onStatus?(status)
    }
}
