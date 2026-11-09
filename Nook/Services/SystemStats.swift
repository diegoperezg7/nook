import Darwin
import Foundation
import IOKit.ps

/// Uso del Mac: CPU, memoria, disco y bateria. Todo con APIs del sistema que
/// funcionan dentro del sandbox.
struct SystemStats: Equatable {
    var cpu: Double = 0
    var memory: Double = 0
    var diskFree: Int64 = 0
    var battery: Int?

    /// Lectura anterior de los contadores de CPU para calcular el uso entre dos llamadas.
    private static var lastTicks: (busy: UInt64, total: UInt64)?

    static func read() -> SystemStats {
        var stats = SystemStats()
        stats.cpu = cpuUsage()
        stats.memory = memoryUsage()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        stats.diskFree = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        stats.battery = batteryLevel()
        return stats
    }

    private static func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice, total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return total > 0 ? Double(busy) / Double(total) : 0 }
        return Double(busy - last.busy) / Double(total - last.total)
    }

    /// Memoria en uso como la cuenta el Monitor de Actividad: app + comprimida + fija.
    private static func memoryUsage() -> Double {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        let used = Double(UInt64(info.internal_page_count) - UInt64(info.purgeable_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    private static func batteryLevel() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let capacity = info[kIOPSCurrentCapacityKey] as? Int else { continue }
            return capacity
        }
        return nil
    }
}
