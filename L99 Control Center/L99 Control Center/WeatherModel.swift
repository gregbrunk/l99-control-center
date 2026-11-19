import AppKit
import CoreLocation
import Foundation
import Observation
import os
import WeatherKit

/// Local weather from Apple WeatherKit, for the keyboard's Real-time page.
/// Asks once for location (approximate is enough), then refreshes every 20 minutes.
@Observable
final class WeatherModel: NSObject {
    nonisolated struct Snapshot: Equatable, Sendable {
        var temperature: Int     // °C
        var high: Int
        var low: Int
        var temperatureF: Int, highF: Int, lowF: Int
        var humidity: Int        // %
        /// The keyboard's 0–5 range: sunny, cloudy, light snow, thunder, rain, heavy snow.
        var condition: Int
        var updated: Date
    }

    private(set) var snapshot: Snapshot?
    private(set) var problem: String?
    /// What it's doing right now, for the menu while there's no weather yet.
    private(set) var step = "Starting…"
    private(set) var markURL: URL?
    private(set) var markDarkURL: URL?
    private(set) var legalURL: URL?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var fetching = false
    /// Retries the location request if Core Location never answers (it sometimes stays silent after a relaunch).
    @ObservationIgnored private var locationWatchdog: Timer?
    @ObservationIgnored private let log = Logger(subsystem: "com.brunk.l99controlcenter", category: "weather")

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        timer?.invalidate()
        timer = nil
        guard on else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        guard enabled else { return }
        switch location.authorizationStatus {
        case .notDetermined:
            step = "Asking for location…"
            location.requestWhenInUseAuthorization()       // the answer arrives in the delegate
        case .denied, .restricted:
            problem = "Location is off for this app. Turn it on in System Settings › Privacy & Security › Location Services."
        default:
            step = "Finding location…"
            // Weather straight away from the last place we knew; a fresh fix replaces it when it comes.
            if let known = location.location ?? Self.savedPlace {
                log.info("location: using the last known place while a new fix comes in")
                if location.location != nil { Self.savedPlace = known }
                fetch(for: known)
            }
            log.info("location: authorised (\(self.location.authorizationStatus.rawValue)), starting updates")
            location.startUpdatingLocation()
            locationWatchdog?.invalidate()
            locationWatchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.enabled, !self.fetching else { return }
                    self.location.stopUpdatingLocation()
                    // Weather from the last known place is fine; the 20-minute refresh tries for a new fix.
                    if self.snapshot != nil { self.log.info("location: no new fix; keeping the last known place"); return }
                    self.log.info("location: no answer after 30 s, retrying")
                    self.step = "Still looking for your location…"
                    self.refresh()
                }
            }
        }
    }

    private func fetch(for place: CLLocation) {
        guard !fetching else { return }
        fetching = true
        step = "Loading weather…"
        Task {
            defer { fetching = false }
            do {
                let (current, daily) = try await WeatherService.shared.weather(for: place, including: .current, .daily)
                let today = daily.forecast.first
                snapshot = Snapshot(
                    temperature: Self.celsius(current.temperature),
                    high: today.map { Self.celsius($0.highTemperature) } ?? Self.celsius(current.temperature),
                    low: today.map { Self.celsius($0.lowTemperature) } ?? Self.celsius(current.temperature),
                    temperatureF: Self.fahrenheit(current.temperature),
                    highF: Self.fahrenheit(today?.highTemperature ?? current.temperature),
                    lowF: Self.fahrenheit(today?.lowTemperature ?? current.temperature),
                    humidity: Int((current.humidity * 100).rounded()),
                    condition: Self.keyboardCode(current.condition),
                    updated: Date())
                problem = nil
                log.info("weather: updated")
                if markURL == nil, let attribution = try? await WeatherService.shared.attribution {
                    markURL = attribution.combinedMarkLightURL
                    markDarkURL = attribution.combinedMarkDarkURL
                    legalURL = attribution.legalPageURL
                }
                onChange?()
            } catch {
                log.error("weather: failed: \(String(describing: error), privacy: .public)")
                if String(describing: error).contains("JWTAuthenticator") {
                    // Apple hasn't activated WeatherKit for this app yet (normal for up to ~30 min after setup).
                    problem = "Apple hasn't switched on weather for this app yet. That can take up to 30 minutes after setup; it retries every 5 minutes."
                } else {
                    problem = "Weather unavailable: \(error.localizedDescription)"
                }
                Task {
                    try? await Task.sleep(for: .seconds(300))
                    refresh()
                }
            }
        }
    }

    /// The last fix, rounded to about 1 km, kept so a relaunch has weather at once.
    private static var savedPlace: CLLocation? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "weather.lat") != nil else { return nil }
            return CLLocation(latitude: d.double(forKey: "weather.lat"), longitude: d.double(forKey: "weather.lon"))
        }
        set {
            guard let p = newValue else { return }
            UserDefaults.standard.set((p.coordinate.latitude * 100).rounded() / 100, forKey: "weather.lat")
            UserDefaults.standard.set((p.coordinate.longitude * 100).rounded() / 100, forKey: "weather.lon")
        }
    }

    private static func celsius(_ m: Measurement<UnitTemperature>) -> Int {
        Int(m.converted(to: .celsius).value.rounded())
    }
    private static func fahrenheit(_ m: Measurement<UnitTemperature>) -> Int {
        Int(m.converted(to: .fahrenheit).value.rounded())
    }

    /// Maps Apple's conditions onto the keyboard's six icons.
    static func keyboardCode(_ c: WeatherCondition) -> Int {
        switch c {
        case .clear, .mostlyClear, .hot, .breezy, .windy, .frigid:
            0
        case .partlyCloudy, .mostlyCloudy, .cloudy, .foggy, .haze, .smoky, .blowingDust:
            1
        case .flurries, .sunFlurries, .sleet, .freezingDrizzle, .wintryMix:
            2
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms, .tropicalStorm, .hurricane:
            3
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingRain, .hail:
            4
        case .snow, .heavySnow, .blizzard, .blowingSnow:
            5
        @unknown default:
            1
        }
    }
}

extension WeatherModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let place = locations.last else { return }
        Task { @MainActor in
            self.log.info("location: got a fix (±\(Int(place.horizontalAccuracy)) m)")
            self.locationWatchdog?.invalidate()
            self.location.stopUpdatingLocation()
            Self.savedPlace = place
            self.fetch(for: place)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.log.error("location: failed: \(message, privacy: .public)")
            // kCLErrorLocationUnknown is temporary; Core Location keeps trying, so keep waiting.
            if (error as? CLError)?.code == .locationUnknown { return }
            self.locationWatchdog?.invalidate()
            self.location.stopUpdatingLocation()
            self.problem = "Couldn't find your location: \(message)"
        }
    }
}
