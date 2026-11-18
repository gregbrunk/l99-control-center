import Foundation
import Observation
import ServiceManagement

/// Wraps SMAppService so the toggle always reflects what macOS actually has.
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var lastError: String?

    /// True when macOS wants the user to approve it in System Settings > General > Login Items.
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
