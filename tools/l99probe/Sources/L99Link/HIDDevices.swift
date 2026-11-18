import Foundation
import IOKit
import IOKit.hid
import L99Core

public struct HIDCollection {
    public let registryID: UInt64
    public let vendor: Int, product: Int
    public let productName: String
    public let usagePage: Int, usage: Int
    public let featureSize: Int, inputSize: Int, outputSize: Int

    public var summary: String {
        String(format: "%04X:%04X  usage %04X:%04X  feature %3d  input %3d  output %3d  \"%@\"  (id %llu)",
               vendor, product, usagePage, usage, featureSize, inputSize, outputSize, productName, registryID)
    }
}

public enum HIDScan {
    public static let wired = (L99Device.wiredKeyboard.vendor, L99Device.wiredKeyboard.product)
    public static let dongle = (L99Device.dongle.vendor, L99Device.dongle.product)

    /// Reads registry properties only. Never opens a device.
    public static func collections(vendor: Int, product: Int) -> [HIDCollection] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var out = [HIDCollection]()
        while case let s = IOIteratorNext(iterator), s != 0 {
            defer { IOObjectRelease(s) }
            func prop(_ k: String) -> Any? { IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            func int(_ k: String) -> Int { (prop(k) as? NSNumber)?.intValue ?? 0 }
            guard int(kIOHIDVendorIDKey) == vendor, int(kIOHIDProductIDKey) == product else { continue }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(s, &id)
            out.append(HIDCollection(registryID: id, vendor: vendor, product: product,
                                     productName: prop(kIOHIDProductKey) as? String ?? "?",
                                     usagePage: int(kIOHIDPrimaryUsagePageKey), usage: int(kIOHIDPrimaryUsageKey),
                                     featureSize: int(kIOHIDMaxFeatureReportSizeKey), inputSize: int(kIOHIDMaxInputReportSizeKey),
                                     outputSize: int(kIOHIDMaxOutputReportSizeKey)))
        }
        return out.sorted { $0.usagePage < $1.usagePage }
    }

    static func open(_ c: HIDCollection) throws -> IOHIDDevice {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(c.registryID))
        guard service != 0 else { throw LinkError("HID device disappeared") }
        defer { IOObjectRelease(service) }
        guard let d = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw LinkError("IOHIDDeviceCreate failed") }
        // Not seized: normal typing keeps working.
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            throw LinkError(String(format: "Could not open HID collection (0x%08X).%@", r,
                                    r == kIOReturnNotPermitted ? " macOS may need Input Monitoring permission for Terminal (System Settings → Privacy & Security)." : ""))
        }
        return d
    }
}

/// Wired keyboard: 64-byte feature reports, report ID 0, on the vendor collection
/// (usage page 0xFF13, usage 1, feature size 64).
public final class WiredKeyboard {
    private let device: IOHIDDevice
    public var verbose = false

    public init() throws {
        let all = HIDScan.collections(vendor: HIDScan.wired.0, product: HIDScan.wired.1)
        let vendor = all.filter { $0.usagePage == 0xFF13 && $0.usage == 1 && $0.featureSize == 64 }
        guard vendor.count == 1, let c = vendor.first else {
            throw LinkError(all.isEmpty ? "Wired keyboard (0C45:800A) not found. Is the USB cable plugged in?"
                                         : "Expected exactly one vendor collection 0xFF13:1 with 64-byte feature reports; found \(vendor.count). Run `l99probe list` and share the output.")
        }
        device = try HIDScan.open(c)
    }
    deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    private func set(_ b: [UInt8]) throws {
        precondition(b.count == 64)
        Thread.sleep(forTimeInterval: 0.035)
        let r = b.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, 64) }
        guard r == kIOReturnSuccess else { throw LinkError(String(format: "SetReport failed (0x%08X)", r)) }
    }
    private func get() throws -> [UInt8] {
        Thread.sleep(forTimeInterval: 0.035)
        var b = [UInt8](repeating: 0, count: 64); var len = 64
        let r = b.withUnsafeMutableBufferPointer { IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &len) }
        guard r == kIOReturnSuccess else { throw LinkError(String(format: "GetReport failed (0x%08X)", r)) }
        return Array(b.prefix(len))
    }

    /// Sends a transaction. Reports that expect an ACK are read back; a busy reply (byte 3 = FF)
    /// is re-read up to 10 times; anything else stops the transaction.
    public func send(_ reports: [WiredReport]) throws {
        for (i, rep) in reports.enumerated() {
            precondition(KeyboardProtocol.allowedOpcodes.contains(rep.bytes[1]) || !rep.expectsAck)
            try set(rep.bytes)
            if verbose { print("  TX \(i + 1):", Array(rep.bytes.prefix(28)).hex) }
            guard rep.expectsAck else { continue }
            var reply = try get()
            var tries = 0
            while KeyboardProtocol.isBusy(reply, for: rep) && tries < 10 { reply = try get(); tries += 1 }
            if verbose { print("  RX \(i + 1):", Array(reply.prefix(12)).hex) }
            guard KeyboardProtocol.isAck(reply, for: rep) else {
                throw LinkError("No ACK for report \(i + 1) (04 \(String(format: "%02X", rep.bytes[1]))): got \(Array(reply.prefix(8)).hex)")
            }
        }
    }
}

/// 2.4 GHz dongle: 32-byte output reports out, input reports back, on the vendor collection.
/// Not thread-safe. Create it, use it and release it on one thread: input reports arrive
/// through that thread's run loop.
public final class Dongle {
    private let device: IOHIDDevice
    private var inbox = [[UInt8]]()
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    public let collection: HIDCollection
    public var verbose = false

    public init() throws {
        let all = HIDScan.collections(vendor: HIDScan.dongle.0, product: HIDScan.dongle.1)
        // Never match on Apple's VID alone: VID+PID, vendor usage page, 32-byte output reports.
        let vendor = all.filter { $0.usagePage >= 0xFF00 && $0.outputSize >= 32 && $0.outputSize <= 33 }
        guard vendor.count == 1, let c = vendor.first else {
            throw LinkError(all.isEmpty ? "Dongle (05AC:024F) not found. Is the 2.4 GHz receiver plugged in?"
                                         : "Expected one dongle vendor collection with 32-byte output reports; found \(vendor.count). Run `l99probe list` and share the output.")
        }
        collection = c
        device = try HIDScan.open(c)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let me = Unmanaged<Dongle>.fromOpaque(ctx).takeUnretainedValue()
            me.inbox.append(Array(UnsafeBufferPointer(start: report, count: length)))
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }

    /// Writes one frame without waiting, as AULA's driver does for music. Returns true if a reply
    /// to this or an earlier frame of the same kind was already waiting (a sign the keyboard is awake).
    @discardableResult
    public func send(_ frame: [UInt8]) throws -> Bool {
        precondition(frame.count == DongleProtocol.size)
        precondition([0x02, 0x20, 0x0C, 0x0B].contains(frame[0]), "only read-only queries, the clock and the music packet are allowed")
        CFRunLoopRunInMode(.defaultMode, 0, true)
        let echoed = inbox.contains { r in
            let reply = r.count == 33 ? Array(r.dropFirst()) : r
            return DongleProtocol.isReply(reply, to: frame)
        }
        inbox.removeAll()
        let r = frame.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, frame.count) }
        guard r == kIOReturnSuccess else { throw LinkError(String(format: "Dongle SetReport failed (0x%08X)", r)) }
        return echoed
    }

    /// Writes one frame and waits up to `timeout` for a reply echoing bytes 0–2. nil = no reply.
    public func transact(_ frame: [UInt8], timeout: TimeInterval = 0.5) throws -> [UInt8]? {
        precondition(frame.count == DongleProtocol.size)
        precondition([0x02, 0x20, 0x0C, 0x0B].contains(frame[0]), "only read-only queries, the clock and the music packet are allowed")
        inbox.removeAll()
        if verbose { print("  TX", frame.hex) }
        let r = frame.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, frame.count) }
        guard r == kIOReturnSuccess else { throw LinkError(String(format: "Dongle SetReport failed (0x%08X)", r)) }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
            while !inbox.isEmpty {
                var reply = inbox.removeFirst()
                if reply.count == 33 { reply.removeFirst() }
                if verbose { print("  RX", reply.hex) }
                if DongleProtocol.isReply(reply, to: frame) { return reply }
            }
        }
        return nil
    }
}
