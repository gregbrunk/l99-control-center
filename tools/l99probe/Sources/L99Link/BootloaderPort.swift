import Darwin
import Foundation
import L99Core
import L99USB
import IOKit

/// The screen's serial port while the keyboard is in bootloader mode (Fn, X, 0, 6).
/// Same USB IDs as normal mode; the bootloader speaks 64-byte packets with 63-byte
/// replies (research/ISP_PROTOCOL.md). Only the interface-flash commands in `ISP` exist.
public final class BootloaderPort {
    private var fd: Int32 = -1
    private var saved = termios()
    private var pending = [UInt8]()
    public let path: String
    public var verbose = false

    /// true = direct USB bulk transfers (L99USB), bypassing macOS's CDC serial driver. Needs root.
    public let direct: Bool

    /// Direct USB: takes the screen from macOS's serial driver (root only) and talks to its
    /// bulk endpoints, one USB transfer per command like Windows. Handed back on deinit.
    /// The screen uses EEEF:268A in both modes; only the USB product name tells them apart:
    /// "USB_VCOM" (serial "TEST_1.0") in bootloader mode, "Generic CDC" in normal mode.
    public static func productNames() -> [String] {
        var it: io_iterator_t = 0
        let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        m["idVendor"] = 0xEEEF; m["idProduct"] = 0x268A
        guard IOServiceGetMatchingServices(kIOMainPortDefault, m, &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var names = [String]()
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            let n = IORegistryEntryCreateCFProperty(s, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            names.append(n ?? "?")
        }
        return names
    }

    public init(directUSB: Bool) throws {
        direct = directUSB
        let names = Self.productNames()
        guard names == ["USB_VCOM"] else {
            throw LinkError(names.isEmpty ? "The screen's USB device isn't connected. Plug in the cable."
                : names.contains("Generic CDC") ? "The screen is in normal mode, not bootloader mode. Hold Fn and tap X, 0, 6, check the screen shows the Bootloader text, then run this again. Nothing was sent."
                : "Unexpected screen USB device(s): \(names). Nothing was sent.")
        }
        guard directUSB else {
            let all = ScreenPort.paths()
            guard all.count == 1, let p = all.first else {
                throw LinkError(all.isEmpty ? "Screen serial port (EEEF:268A) not found. Is the USB cable plugged in and the keyboard in bootloader mode (Fn, X, 0, 6)?"
                                             : "More than one L99 screen port found: \(all). Unplug the extras.")
            }
            path = p
            try openPort(fast: false)
            return
        }
        guard getuid() == 0 else { throw LinkError("Direct USB needs administrator rights: run this command with sudo.") }
        path = "USB EEEF:268A (direct)"
        var err = [CChar](repeating: 0, count: 256)
        guard l99usb_open(0xEEEF, 0x268A, 1, &err, Int32(err.count)) == 0 else {
            throw LinkError(String(cString: err))
        }
        var d = [CChar](repeating: 0, count: 256)
        l99usb_describe(&d, Int32(d.count))
        info = String(cString: d)
    }

    /// Direct USB: what was opened, for the log.
    public private(set) var info = ""

    var isFast = false

    /// Opens the port the way Windows did in the capture: 8N1 at the given rate, then
    /// DTR and RTS low (SET_CONTROL_LINE_STATE 0). macOS raises both on open.
    /// 921600 has no B-constant on macOS, so it goes through IOSSIOSPEED.
    func openPort(fast: Bool) throws {
        if direct { isFast = fast; return }
        if fd >= 0 { tcsetattr(fd, TCSANOW, &saved); Darwin.close(fd); fd = -1 }
        pending.removeAll()
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw LinkError("Could not open \(path): \(String(cString: strerror(errno)))") }
        guard tcgetattr(fd, &saved) == 0 else { Darwin.close(fd); fd = -1; throw LinkError("tcgetattr failed") }
        var t = saved
        cfmakeraw(&t)
        t.c_cflag = tcflag_t(CS8 | CREAD | CLOCAL)
        cfsetispeed(&t, speed_t(B115200)); cfsetospeed(&t, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { Darwin.close(fd); fd = -1; throw LinkError("tcsetattr failed") }
        if fast {
            var speed = speed_t(921_600)
            let IOSSIOSPEED: UInt = 0x8008_5402   // _IOW('T', 2, speed_t)
            guard ioctl(fd, IOSSIOSPEED, &speed) == 0 else { throw LinkError("Could not set 921600: \(String(cString: strerror(errno)))") }
        }
        var lines = Int32(TIOCM_DTR | TIOCM_RTS)
        let TIOCMBIC: UInt = 0x8004_746B          // _IOW('t', 107, int)
        guard ioctl(fd, TIOCMBIC, &lines) == 0 else { throw LinkError("Could not lower DTR/RTS: \(String(cString: strerror(errno)))") }
        tcflush(fd, TCIOFLUSH)
        isFast = fast
        if verbose { print("  (port open at \(fast ? 921_600 : 115_200), DTR/RTS low)") }
    }

    deinit {
        if direct { l99usb_close() }
        if fd >= 0 { tcsetattr(fd, TCSANOW, &saved); Darwin.close(fd) }
    }

    func send(_ bytes: [UInt8]) throws {
        if verbose { print("  TX", bytes.prefix(20).hex, bytes.count > 20 ? "… (\(bytes.count) B)" : "") }
        if direct {
            guard l99usb_write(bytes, UInt32(bytes.count), 3000) == 0 else {
                throw LinkError(String(format: "USB write failed (IOReturn 0x%08X)", UInt32(bitPattern: l99usb_last_error())))
            }
            return
        }
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

    /// One 63-byte reply, or nil on timeout.
    func reply(timeout: TimeInterval) throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        while direct && pending.count < ISP.replyLength {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { return nil }
            var buf = [UInt8](repeating: 0, count: 64)
            let n = l99usb_read(&buf, 64, UInt32(max(1, left * 1000)))
            if n < 0 { throw LinkError(String(format: "USB read failed (IOReturn 0x%08X)", UInt32(bitPattern: l99usb_last_error()))) }
            if n == 0 { return nil }
            pending += buf.prefix(Int(n))
        }
        while pending.count < ISP.replyLength {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, Int32(min(left, 0.05) * 1000) + 1) > 0 else { continue }
            guard pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) == 0 else { throw LinkError("Screen disconnected") }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 { pending += buf.prefix(n) }
            else if n == 0 || (errno != EAGAIN && errno != EINTR) { throw LinkError("Screen disconnected while reading") }
        }
        let r = Array(pending.prefix(ISP.replyLength))
        pending.removeFirst(ISP.replyLength)
        if verbose { print("  RX", r.prefix(20).hex) }
        return r
    }

    /// Sends one command and returns its reply. Throws on timeout or stray bytes.
    func exchange(_ packet: [UInt8], timeout: TimeInterval = 2) throws -> [UInt8] {
        guard pending.isEmpty else { throw LinkError("Unexpected extra bytes from the screen: \(pending.prefix(16).hex). Stopped.") }
        // AULA's tool leaves ~50–60 ms between commands (captured); the bootloader
        // does not answer a command sent straight after the previous reply.
        usleep(60_000)
        try send(packet)
        guard let r = try reply(timeout: timeout) else {
            throw LinkError(String(format: "No reply to command %02X within %.0f s. Is the keyboard in bootloader mode?", packet[0], timeout))
        }
        return r
    }

    // MARK: Steps

    var connected = false

    /// AULA's nonce: local time folded into 32 bits (0x401f80), so it moves on by
    /// milliseconds between commands and never repeats within a session.
    static func clockNonce() -> UInt32 {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: Date())
        let ms = (c.nanosecond ?? 0) / 1_000_000
        let v = ((c.year ?? 2026) - 2000) * ms + (c.month ?? 1) * 0xFD200 + (c.day ?? 1) * 0x15180
            + (c.hour ?? 0) * 0xE10 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return UInt32(truncatingIfNeeded: v)
    }
    var lastNonce: UInt32 = 0
    public var handshakeTimeout: TimeInterval = 2

    /// `4B` handshake; checks the key and the info bytes against the capture.
    /// The first one in a session copies AULA's tool: two `08` hellos at 115200, then the
    /// port is closed and reopened at 921600 for everything else (all `7F`).
    /// No fallback: no reply at 115200 means stop (power-cycle and re-enter bootloader).
    /// Mac tests (Nov 18): every `08` handshake at 115200 was answered; switching the line to
    /// 921600 for the `7F` handshakes is where the screen went silent. So by default the Mac
    /// stays at 115200 with `08` throughout. `useFastLine` keeps AULA's switch for testing.
    public var useFastLine = false

    public func handshake(_ target: ISP.Target) throws {
        if !connected {
            // The first hello is retried: in direct mode the screen sometimes misses the first
            // one after a cold start (Nov 18), and a repeated hello changes nothing on the screen.
            var firstOK = false
            for attempt in 1...4 where !firstOK {
                do { try rawHandshake(.hello); firstOK = true } catch {
                    if attempt == 4 { break }
                    if verbose { print("  (no answer to hello \(attempt) of 4; waiting 1 s)") }
                    pending.removeAll()
                    usleep(1_000_000)
                }
            }
            do { if !firstOK { throw LinkError("no reply to 4 hellos") } } catch {
                throw LinkError("The bootloader did not answer the first handshake. Unplug the cable for 5 s, plug it back in, press Fn, X, 0, 6 again, and run this once. (\(error))")
            }
            connected = true
            if useFastLine {
                usleep(30_000)
                try openPort(fast: true)
                try rawHandshake(.hello)
            }
            if target == .hello { return }
        }
        try rawHandshake(target)
    }

    func rawHandshake(_ target: ISP.Target) throws {
        var n = Self.clockNonce()
        if n == lastNonce { n &+= 1 }
        lastNonce = n
        let request = ISP.handshake(target, nonce: n, fast: isFast)
        try ISP.checkHandshake(try exchange(request, timeout: handshakeTimeout), request: request)
    }

    /// `6D`: flash ID must be the GD5F1GQ4.
    public func checkFlashID() throws { try ISP.checkFlashID(try exchange(ISP.flashIDRequest, timeout: 10)) }

    /// READ-ONLY probe: hello handshake and flash ID. Writes nothing to flash.
    public func probe() throws {
        try handshake(.hello)
        try checkFlashID()
    }

    /// `4F 08008000`: leave the bootloader and run the keyboard's normal screen firmware.
    /// A bare 4F on a fresh connection was ignored (Nov 18); after a handshake it matches the PC session.
    public func restart(handshakeFirst: Bool = true) throws {
        if handshakeFirst { try handshake(.hello) }
        usleep(60_000)
        try send(ISP.restartRequest)
    }

    public enum Phase { case writing, verifying }

    /// Installs a whole interface file: 4B 30, 4B 32, 6D, 6F 02, 6C × n, 6E (checked as it
    /// runs), then 4F. Returns the screen's final read-back value.
    public func install(_ image: ISP.Image, restartWhenDone: Bool = true, setupOnly: Bool = false,
                        progress: (Phase, Int, Int) -> Void) throws -> UInt32? {
        let quiet = !verbose
        verbose = true          // always log the setup commands
        try handshake(.hello)
        try handshake(.interface)
        try checkFlashID()
        if setupOnly { return nil }     // stop before 6F and before any write
        try ISP.checkAddressMode(try exchange(ISP.addressModeRequest))
        verbose = !quiet

        let n = image.chunkCount
        for i in 0..<n {
            let packet = image.packet(i)
            let toggle = UInt8(i & 1)
            var accepted = false
            for attempt in 1...3 {
                if attempt > 1 { if !direct { tcflush(fd, TCIFLUSH) }; pending.removeAll() }
                try send(packet)
                if let r = try reply(timeout: 2), ISP.dataAccepted(r, toggle: toggle) { accepted = true; break }
                if verbose { print("  chunk \(i): attempt \(attempt) not accepted") }
            }
            guard accepted else {
                throw LinkError("Chunk \(i + 1) of \(n) (offset 0x\(String(i * ISP.chunkSize, radix: 16))) was not accepted after 3 tries. Stopped. The screen is still in bootloader mode; run the install again or use the PC reset tool.")
            }
            if i % 64 == 0 || i == n - 1 { progress(.writing, i + 1, n) }
        }

        try send(ISP.verifyRequest(size: image.bytes.count, fileCRC: image.crc))
        var tracker = ISP.VerifyTracker(image)
        while true {
            guard let r = try reply(timeout: 5) else { throw LinkError("The screen stopped reporting during the read-back check. Stopped.") }
            switch try ISP.parseVerify(r) {
            case let .progress(position, crc):
                try tracker.check(position: position, runningCRC: crc)
                progress(.verifying, min(position, image.bytes.count), image.bytes.count)
            case let .done(value):
                guard tracker.checked > 0 else { throw LinkError("The read-back check finished without any progress reports. Stopped.") }
                if restartWhenDone { try restart(handshakeFirst: false) }
                return value
            }
        }
    }
}
