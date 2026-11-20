import AppKit
import SwiftUI

/// Entry point. With `--install-interface` the executable runs as the screen installer (started by
/// the app with administrator rights, see InterfaceInstaller); otherwise it's the menu bar app.
@main
enum Entry {
    static func main() {
        if let code = InterfaceInstaller.runIfRequested(CommandLine.arguments) { exit(code) }
        #if DEBUG
        MigrationCommand.runIfRequested()
        IconRenderer.renderIfRequested()
        DebugSnapshot.renderIfRequested()
        #endif
        L99ControlCenterApp.main()
    }
}

/// Menu bar only (LSUIElement = YES): no Dock icon. One window, with a tab per section, opens from the dropdown.
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

        Window("L99 Control Center", id: WindowID.main) {
            MainWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1260, height: 830)
    }
}

enum WindowID {
    static let main = "main"
}

/// Opens the app's window on a tab and brings it to the front (the app has no Dock icon).
struct WindowOpener {
    let openWindow: OpenWindowAction
    let model: AppModel

    func callAsFunction(_ tab: AppTab) {
        model.tab = tab
        openWindow(id: WindowID.main)
        NSApp.activate(ignoringOtherApps: true)
    }
}
