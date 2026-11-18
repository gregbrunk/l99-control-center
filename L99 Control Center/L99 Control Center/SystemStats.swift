import Darwin
import Foundation
import IOKit

/// CPU and GPU load. Public APIs only: host CPU ticks, and the GPU's own
/// "Device Utilization %" in the IORegistry. Use from one thread.
nonisolated final class SystemStats {
    private let host = mach_host_self()
    private var previous: (busy: UInt64, total: UInt64)?

    /// Percent of all cores busy since the previous call. nil on the first call.
    func cpuPercent() -> Int? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let now = (busy: user + system + nice, total: user + system + nice + idle)
        defer { previous = now }
        guard let previous, now.total > previous.total else { return nil }
        let percent = Double(now.busy - previous.busy) / Double(now.total - previous.total) * 100
        return min(100, max(0, Int(percent.rounded())))
    }

    /// The busiest GPU's utilisation, as the GPU driver reports it.
    func gpuPercent() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.intValue else { continue }
            best = max(best ?? 0, min(100, max(0, value)))
        }
        return best
    }
}
