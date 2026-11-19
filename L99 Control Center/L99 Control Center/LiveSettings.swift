import Foundation
import Observation

/// The live-data switches and music settings, kept in UserDefaults.
@Observable
final class LiveSettings {
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var clock: Bool { didSet { save(clock, "live.clock") } }
    var load: Bool { didSet { save(load, "live.load") } }
    var weather: Bool { didSet { save(weather, "live.weather") } }
    var music: Bool { didSet { save(music, "music.enabled") } }
    /// US units: 12-hour clock and °F. Otherwise 24-hour and °C.
    var usUnits: Bool { didSet { save(usUnits, "units.us") } }
    /// 0...1, how tall quiet music looks.
    var sensitivity: Double { didSet { save(sensitivity, "music.sensitivity") } }
    /// The two style bytes in the music packet. AULA's driver sends 2 and 0. Mapped Nov 18 on Alison's keyboard:
    /// they are the same key-light visualiser in two directions. The first byte draws it **up from the bottom**,
    /// the second **down from the top**; the value picks the colours (0 = off). Using both at once clashes.
    /// Neither changes the screen's bars. Set them through `direction` and `palette`.
    private(set) var foreMode: Int { didSet { save(foreMode, "music.foreMode") } }
    private(set) var backMode: Int { didSet { save(backMode, "music.backMode") } }

    /// 0 = off (screen only), 1 = up from the bottom, 2 = down from the top.
    var direction: Int { didSet { save(direction, "music.direction"); applyStyle() } }
    /// Index into `palettes`.
    var palette: Int { didSet { save(palette, "music.palette"); applyStyle() } }

    static let directions: [(value: Int, name: String)] = [
        (1, "Up from the bottom (AULA's default)"),
        (2, "Down from the top"),
        (0, "Off (screen only)"),
    ]

    /// Colour sets, with the byte value that gives each one in each direction (Rainbow and Unicorn swap).
    static let palettes: [(name: String, up: Int, down: Int)] = [
        ("Rainbow", 2, 3),
        ("Unicorn rainbow", 3, 2),
        ("Rotating rainbow", 4, 4),
        ("Pulsing colour cycle", 5, 5),
        ("Green, yellow and red", 1, 1),
        ("Lavender", 6, 6),
        ("Red", 7, 7),
        ("Amber", 8, 8),
        ("Yellow", 9, 9),
    ]

    private func applyStyle() {
        let p = Self.palettes[min(max(palette, 0), Self.palettes.count - 1)]
        foreMode = direction == 1 ? p.up : 0
        backMode = direction == 2 ? p.down : 0
    }

    init() {
        defaults.register(defaults: [
            "live.clock": true, "live.load": true, "live.weather": true, "music.enabled": false,
            "music.sensitivity": 0.5, "music.direction": 1, "music.palette": 0,
            "units.us": Locale.current.measurementSystem == .us,
        ])
        usUnits = defaults.bool(forKey: "units.us")
        clock = defaults.bool(forKey: "live.clock")
        load = defaults.bool(forKey: "live.load")
        weather = defaults.bool(forKey: "live.weather")
        music = defaults.bool(forKey: "music.enabled")
        sensitivity = defaults.double(forKey: "music.sensitivity")
        direction = defaults.integer(forKey: "music.direction")
        palette = defaults.integer(forKey: "music.palette")
        foreMode = 2
        backMode = 0
        applyStyle()
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
