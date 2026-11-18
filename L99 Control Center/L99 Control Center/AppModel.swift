import Foundation
import Observation

/// Everything the windows share. Created once by the App.
@Observable
final class AppModel {
    let devices: DeviceMonitor
    let library: Library
    let transfer: ScreenTransferController
    let keyboard: KeyboardLink
    let settings: LiveSettings
    let weather: WeatherModel
    let launchAtLogin = LaunchAtLogin()

    init() {
        let devices = DeviceMonitor()
        let library = Library()
        self.devices = devices
        self.library = library
        let transfer = ScreenTransferController(library: library)
        let settings = LiveSettings()
        let weather = WeatherModel()
        self.transfer = transfer
        self.settings = settings
        self.weather = weather
        keyboard = KeyboardLink(devices: devices, transfer: transfer, settings: settings, weather: weather)
        devices.onChange = { [weak keyboard] in keyboard?.connectionChanged() }
    }
}
