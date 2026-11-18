import AppKit
import SwiftUI

/// Menu bar only (LSUIElement = YES): no Dock icon. Windows open from the dropdown.
@main
struct L99ControlCenterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.devices.connection == .none ? "keyboard" : "keyboard.fill")
                .accessibilityLabel("L99 Control Center")
        }
        .menuBarExtraStyle(.window)

        Window("Upload to Screen", id: WindowID.upload) {
            UploadView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Library", id: WindowID.library) {
            LibraryView(model: model)
        }
        .defaultSize(width: 900, height: 640)

        Window("Recovery", id: WindowID.recovery) {
            RecoveryView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Music and Key Lighting", id: WindowID.music) {
            MusicView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let upload = "upload"
    static let library = "library"
    static let recovery = "recovery"
    static let music = "music"
}

/// Opens one of the app's windows and brings it to the front (the app has no Dock icon).
struct WindowOpener {
    let openWindow: OpenWindowAction

    func callAsFunction(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
