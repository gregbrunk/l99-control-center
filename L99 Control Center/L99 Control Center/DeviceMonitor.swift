import Foundation
import IOKit
import IOKit.usb
import L99Core
import Observation

/// Watches USB for the keyboard, dongle and screen.
/// Read-only: it looks at the IORegistry and never opens or writes to a device.
@Observable
final class DeviceMonitor {
    enum Connection: Equatable {
        case none
        case dongle
        case cable
        case cableAndDongle
    }

    private(set) var wiredKeyboard = false
    private(set) var dongle = false
    /// The touchscreen's serial port. Uploads need this.
    private(set) var screen = false

    var connection: Connection {
        switch (wiredKeyboard || screen, dongle) {
        case (true, true): .cableAndDongle
        case (true, false): .cable
        case (false, true): .dongle
        case (false, false): .none
        }
    }

    var connectionDescription: String {
        switch connection {
        case .none: "Not connected"
        case .dongle: "2.4 GHz dongle"
        case .cable: "USB cable"
        case .cableAndDongle: "USB cable and 2.4 GHz dongle"
        }
    }

    /// Called on the main thread when the keyboard, dongle or screen comes or goes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var port: IONotificationPortRef?
    @ObservationIgnored private var iterators: [io_iterator_t] = []

    init() {
        rescan()
        startNotifications()
    }

    deinit {
        iterators.forEach { IOObjectRelease($0) }
        if let port { IONotificationPortDestroy(port) }
    }

    func rescan() {
        let present = Self.presentUSBIDs()
        let before = (wiredKeyboard, dongle, screen)
        wiredKeyboard = present.contains(L99Device.wiredKeyboard)
        dongle = present.contains(L99Device.dongle)
        screen = present.contains(L99Device.screen)
        if before != (wiredKeyboard, dongle, screen) { onChange?() }
    }

    /// All vendor/product pairs currently on USB.
    private static func presentUSBIDs() -> Set<USBID> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var ids = Set<USBID>()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
            }
            if let vendor = number(kUSBVendorID), let product = number(kUSBProductID) {
                ids.insert(USBID(vendor: vendor, product: product))
            }
        }
        return ids
    }

    /// Rescans whenever any USB device arrives or leaves.
    private func startNotifications() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            // Drain the iterator to re-arm the notification.
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            guard let context else { return }
            let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.rescan() }
        }

        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOUSBHostDevice"), callback, context, &iterator)
            guard result == KERN_SUCCESS else { continue }
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            iterators.append(iterator)
        }
    }
}
