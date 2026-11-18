// USB IDs of the three AULA L99 devices. Confirmed on hardware (FINDINGS.md).

public struct USBID: Hashable, Sendable {
    public let vendor: Int
    public let product: Int
    public init(vendor: Int, product: Int) {
        self.vendor = vendor
        self.product = product
    }
}

public enum L99Device {
    /// Keyboard over the USB cable (HID collection FF13:0001, 64-byte feature reports).
    public static let wiredKeyboard = USBID(vendor: 0x0C45, product: 0x800A)
    /// 2.4 GHz dongle (HID collection FF60:0061, 32-byte reports).
    public static let dongle = USBID(vendor: 0x05AC, product: 0x024F)
    /// Touchscreen serial port ("Generic CDC"). Only present with the USB cable.
    public static let screen = USBID(vendor: 0xEEEF, product: 0x268A)
}
