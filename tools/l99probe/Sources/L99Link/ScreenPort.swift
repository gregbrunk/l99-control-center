import Darwin
import Foundation
import IOKit
import IOKit.serial
import L99Core

/// Any failure talking to the keyboard, dongle or screen. The message is shown to the user as is.
public struct LinkError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public init(_ s: String) { description = s }
    public var errorDescription: String? { description }
}

/// The screen's USB serial port (EEEF:268A). Found by walking up from each
/// IOSerialBSDClient to its USB device and matching VID/PID — never by name.
public final class ScreenPort {
    static let vendor = 0xEEEF, product = 0x268A

    public static func paths() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found = [String]()
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { continue }
            var entry = service
            IOObjectRetain(entry)
            while entry != 0 {
                let v = IORegistryEntryCreateCFProperty(entry, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
                let p = IORegistryEntryCreateCFProperty(entry, "idProduct" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
                if v?.intValue == vendor && p?.intValue == product { found.append(path); break }
                var parent: io_registry_entry_t = 0
                let r = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
                IOObjectRelease(entry)
                entry = r == KERN_SUCCESS ? parent : 0
            }
            if entry != 0 { IOObjectRelease(entry) }
        }
        return found
    }

    private var fd: Int32 = -1
    private var saved = termios()
    private var parser = ScreenProtocol.ResponseParser()
    public let path: String
    public var verbose = false

    public init() throws {
        let all = Self.paths()
        guard all.count == 1, let p = all.first else {
            throw LinkError(all.isEmpty ? "Screen serial port (EEEF:268A) not found. Is the USB cable plugged in and the keyboard switched on?"
                                         : "More than one L99 screen port found: \(all). Unplug the extras.")
        }
        path = p
        fd = Darwin.open(p, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw LinkError("Could not open \(p): \(String(cString: strerror(errno)))") }
        guard tcgetattr(fd, &saved) == 0 else { Darwin.close(fd); throw LinkError("tcgetattr failed") }
        var t = saved
        cfmakeraw(&t)
        t.c_cflag = tcflag_t(CS8 | CREAD | CLOCAL)
        cfsetispeed(&t, speed_t(B115200)); cfsetospeed(&t, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { Darwin.close(fd); throw LinkError("tcsetattr failed") }
        tcflush(fd, TCIOFLUSH)
    }

    deinit {
        if fd >= 0 { tcsetattr(fd, TCSANOW, &saved); Darwin.close(fd) }
    }

    private func write(_ bytes: [UInt8]) throws {
        let deadline = Date().addingTimeInterval(3)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset) }
            if n > 0 { offset += n; continue }
            guard errno == EAGAIN || errno == EINTR else { throw LinkError("Screen disconnected while sending (\(String(cString: strerror(errno))))") }
            guard Date() < deadline else { throw LinkError("Screen stopped accepting data") }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0); _ = poll(&pfd, 1, 25)
        }
    }

    private func reply(timeout: TimeInterval) throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let body = try parser.next() { return body }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 25) > 0 {
                guard pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) == 0 else { throw LinkError("Screen disconnected") }
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 { parser.feed(Array(buf.prefix(n))) }
                else if n == 0 || (errno != EAGAIN && errno != EINTR) { throw LinkError("Screen disconnected while reading") }
            }
        }
        throw LinkError("Timed out after \(timeout)s waiting for the screen to reply")
    }

    /// READ-ONLY: reads `count` runtime words at `address` (short `03` frame, bounds-checked in RuntimeMemory).
    public func readWords(address: UInt16, count: Int) throws -> [UInt16] {
        let frame = try RuntimeMemory.readFrame(address: address, count: count)
        if verbose { print("  TX", frame.hex) }
        try write(frame)
        for _ in 0..<2 {
            let body = try reply(timeout: 2)
            if verbose { print("  RX", body.hex) }
            if let words = try RuntimeMemory.words(fromReply: body, address: address, count: count) { return words }
        }
        throw LinkError("The screen only acknowledged the memory read and sent no data. Stopped.")
    }

    /// Sends one request, then requires an ACK body `[cmd, FF]` and a result body
    /// `[cmd, addr(4), …]` with the same address. Any deviation throws (= stop).
    public func request(_ command: UInt8, address: UInt32, data: [UInt8]) throws -> [UInt8] {
        let frame = ScreenProtocol.requestFrame(command: command, address: address, data: data)
        if verbose { print("  TX", frame.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "), frame.count > 16 ? "… (\(frame.count) B)" : "") }
        try write(frame)
        let ack = try reply(timeout: 3)
        if verbose { print("  RX", ack.hex) }
        guard ack == [command, 0xFF] else { throw LinkError("Screen rejected command 0x\(String(format: "%02X", command)): \(ack.hex)") }
        let result = try reply(timeout: 3)
        if verbose { print("  RX", result.hex, String(bytes: result.filter { (0x20...0x7E).contains($0) }, encoding: .ascii) ?? "") }
        guard result.count >= 5, result[0] == command, ScreenProtocol.beValue(result[1..<5]) == address else {
            throw LinkError("Screen confirmed the wrong command/address: \(result.hex)")
        }
        return result
    }
}
