import Foundation
import L99Core
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
    let skins = SkinStore()
    /// The single window's open tab; the menu bar's links set it.
    var tab: AppTab = .library
    /// Kept here so the Upload tab keeps its picture and settings when you switch tabs.
    let upload = UploadModel()
    var libraryFilter: ScreenProtocol.Slot?
    var librarySearch = ""

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
        skins.fahrenheit = settings.usUnits
        skins.onInstalled = { [weak library] kept in library?.interfaceInstalled(kept: kept) }
        skins.contentToKeep = { [weak library] background in library?.contentToKeep(includeBackground: background) ?? [] }
    }

    /// One switch for the live data and the skin's Data page label.
    func setUSUnits(_ us: Bool) {
        settings.usUnits = us
        skins.fahrenheit = us
    }
}
