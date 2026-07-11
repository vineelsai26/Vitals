import Darwin
import Foundation
import IOKit.ps
import Metal
import SystemConfiguration

public actor SystemMetricsSampler {
    private var collector = SystemMetricsCollector()

    public init() {}

    public func sample() -> SystemSnapshot {
        collector.sample()
    }
}

struct SystemMetricsCollector {
    private var previousCPU: CPUTicks?
    private var previousNetworkByInterface: [String: NetworkCounters] = [:]
    private var previousNetworkDate: Date?
    private var processCPUBaseline: [Int32: (user: UInt64, system: UInt64, at: Date)] = [:]
    private let processorName = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple processor"
    private let isAppleSilicon = Self.sysctlInt("hw.optional.arm64") == 1
    private let gpuName = MTLCreateSystemDefaultDevice()?.name
    private var lastProcessRefresh = Date.distantPast
    private var cachedProcesses: [ProcessMetric] = []

    mutating func sample(at now: Date = Date()) -> SystemSnapshot {
        let currentCPU = Self.cpuTicks()
        let cpuUsage: Double
        if let previousCPU, let currentCPU {
            cpuUsage = CPUTicks.utilization(previous: previousCPU, current: currentCPU)
        } else {
            cpuUsage = 0
        }
        if let currentCPU { previousCPU = currentCPU }

        let primary = Self.primaryInterfaceName()
        let interfaceCounters = Self.allInterfaceCounters()
        var interfaceMetrics: [NetworkInterfaceMetric] = []
        var totalDown = 0.0
        var totalUp = 0.0
        let elapsed = previousNetworkDate.map { now.timeIntervalSince($0) } ?? 0

        for (name, counters) in interfaceCounters {
            var down = 0.0
            var up = 0.0
            if let previous = previousNetworkByInterface[name], elapsed > 0 {
                let rates = NetworkCounters.rates(previous: previous, current: counters, elapsed: elapsed)
                down = rates.download
                up = rates.upload
            }
            totalDown += down
            totalUp += up
            interfaceMetrics.append(
                NetworkInterfaceMetric(
                    name: name,
                    downloadBytesPerSecond: down,
                    uploadBytesPerSecond: up,
                    isPrimary: name == primary
                )
            )
        }
        interfaceMetrics.sort {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return ($0.downloadBytesPerSecond + $0.uploadBytesPerSecond)
                > ($1.downloadBytesPerSecond + $1.uploadBytesPerSecond)
        }
        previousNetworkByInterface = interfaceCounters
        previousNetworkDate = now

        let memory = Self.memoryBreakdown()
        let disk = Self.diskUsage()
        let battery = Self.batteryStatus()
        if now.timeIntervalSince(lastProcessRefresh) >= 3 {
            cachedProcesses = sampleProcesses(at: now, limit: 25)
            lastProcessRefresh = now
        }

        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)

        return SystemSnapshot(
            capturedAt: now,
            cpuUsage: cpuUsage,
            memoryUsedBytes: memory.usedBytes,
            memoryTotalBytes: memory.totalBytes,
            memory: memory,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            diskVolumeName: disk.volumeName,
            downloadBytesPerSecond: totalDown,
            uploadBytesPerSecond: totalUp,
            primaryInterfaceName: primary,
            networkInterfaces: Array(interfaceMetrics.prefix(8)),
            loadAverage: loads[0],
            loadAverage5: loads[1],
            loadAverage15: loads[2],
            uptime: ProcessInfo.processInfo.systemUptime,
            thermalLevel: Self.thermalLevel,
            processorName: processorName,
            processorCount: ProcessInfo.processInfo.processorCount,
            gpuName: gpuName ?? "GPU unavailable",
            gpuAvailability: gpuName == nil ? .unavailable : .detected,
            neuralEngineName: isAppleSilicon ? "Apple Neural Engine" : "Neural Engine unavailable",
            neuralEngineAvailability: isAppleSilicon ? .detected : .unavailable,
            batteryLevel: battery.level,
            batteryPowerState: battery.state,
            batteryTimeRemaining: battery.timeRemaining,
            topProcesses: cachedProcesses,
            topProcessLimit: 25
        )
    }

    private static var thermalLevel: ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }

    private static func cpuTicks() -> CPUTicks? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var resultTicks = CPUTicks(user: 0, system: 0, nice: 0, idle: 0)
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * stride
            resultTicks.user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            resultTicks.system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            resultTicks.nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            resultTicks.idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
        }
        return resultTicks
    }

    private static func memoryBreakdown() -> MemoryBreakdown {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let swap = swapUsage()
        guard result == KERN_SUCCESS else {
            return MemoryBreakdown(totalBytes: total, swapUsedBytes: swap.used, swapTotalBytes: swap.total)
        }
        let pageSize = UInt64(vm_kernel_page_size)
        return MemoryBreakdown(
            totalBytes: total,
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            activeBytes: UInt64(stats.active_count) * pageSize,
            inactiveBytes: UInt64(stats.inactive_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            freeBytes: UInt64(stats.free_count) * pageSize,
            speculativeBytes: UInt64(stats.speculative_count) * pageSize,
            purgeableBytes: UInt64(stats.purgeable_count) * pageSize,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total
        )
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard status == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private static func diskUsage() -> (used: UInt64, total: UInt64, volumeName: String) {
        let root = URL(fileURLWithPath: "/")
        do {
            let values = try root.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeNameKey,
            ])
            let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
            let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let volumeName = (name?.isEmpty == false) ? name! : "Macintosh HD"
            return (total > available ? total - available : 0, total, volumeName)
        } catch {
            return (0, 0, "Macintosh HD")
        }
    }

    private static func allInterfaceCounters() -> [String: NetworkCounters] {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else { return [:] }
        defer { freeifaddrs(addressPointer) }

        var result: [String: (received: UInt64, sent: UInt64)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                var entry = result[name] ?? (0, 0)
                entry.received &+= UInt64(data.pointee.ifi_ibytes)
                entry.sent &+= UInt64(data.pointee.ifi_obytes)
                result[name] = entry
            }
            pointer = interface.ifa_next
        }
        return result.mapValues { NetworkCounters(receivedBytes: $0.received, sentBytes: $0.sent) }
    }

    private static func primaryInterfaceName() -> String? {
        guard let value = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString),
              let dictionary = value as? [String: Any] else { return nil }
        return dictionary[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }

    private static func batteryStatus() -> (
        level: Double?,
        state: BatteryPowerState,
        timeRemaining: TimeInterval?
    ) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return (nil, .noBattery, nil)
        }

        let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let level = current.flatMap { current in
            maximum.flatMap { maximum in maximum > 0 ? current / maximum : nil }
        }
        let isChargingFlag = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let onAC = powerState == kIOPSACPowerValue

        let state: BatteryPowerState
        if level == nil {
            state = .noBattery
        } else if isChargingFlag {
            state = .charging
        } else if onAC {
            state = .chargedOnAC
        } else {
            state = .onBattery
        }

        let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.doubleValue
        let remaining: TimeInterval? = {
            guard state == .onBattery, let minutes, minutes > 0 else { return nil }
            return minutes * 60
        }()
        return (level, state, remaining)
    }

    private mutating func sampleProcesses(at now: Date, limit: Int) -> [ProcessMetric] {
        var pids = [pid_t](repeating: 0, count: 4_096)
        let bytes = Int32(MemoryLayout<pid_t>.stride * pids.count)
        let count = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            return proc_listallpids(base, bytes)
        }
        guard count > 0 else { return fallbackProcessesViaPS(limit: limit) }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        var metrics: [ProcessMetric] = []
        metrics.reserveCapacity(Int(count))
        var seen: Set<Int32> = []

        for index in 0..<Int(count) {
            let pid = pids[index]
            guard pid > 0, pid != selfPID, seen.insert(pid).inserted else { continue }

            var taskInfo = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize)
            guard taskResult == taskSize else { continue }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
            let path = pathLength > 0 ? String(cString: pathBuffer) : nil
            let name: String = {
                if let path, !path.isEmpty {
                    return URL(fileURLWithPath: path).lastPathComponent
                }
                var nameBuffer = [CChar](repeating: 0, count: 32)
                if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
                    return String(cString: nameBuffer)
                }
                return "pid \(pid)"
            }()

            let user = UInt64(taskInfo.pti_total_user)
            let system = UInt64(taskInfo.pti_total_system)
            // pti_total_user/system are in nanoseconds.
            let cpuUsage: Double
            if let previous = processCPUBaseline[pid] {
                let elapsed = now.timeIntervalSince(previous.at)
                let deltaNanos = Double((user &- previous.user) &+ (system &- previous.system))
                let cpuSeconds = deltaNanos / 1_000_000_000
                let maxPercent = 100 * Double(ProcessInfo.processInfo.processorCount)
                cpuUsage = elapsed > 0
                    ? min(max((cpuSeconds / elapsed) * 100, 0), maxPercent)
                    : 0
            } else {
                cpuUsage = 0
            }
            processCPUBaseline[pid] = (user, system, now)
            metrics.append(
                ProcessMetric(
                    pid: pid,
                    name: name,
                    cpuUsage: cpuUsage,
                    memoryBytes: UInt64(taskInfo.pti_resident_size),
                    path: path
                )
            )
        }

        // Drop baselines for dead PIDs
        let live = Set(metrics.map(\.pid))
        processCPUBaseline = processCPUBaseline.filter { live.contains($0.key) }

        return metrics
            .sorted { $0.cpuUsage > $1.cpuUsage }
            .prefix(limit)
            .map { $0 }
    }

    private func fallbackProcessesViaPS(limit: Int) -> [ProcessMetric] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return [] }
            return output.split(separator: "\n").compactMap { line -> ProcessMetric? in
                let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count == 4,
                      let pid = Int32(fields[0]),
                      let cpu = Double(fields[1]),
                      let rssKB = UInt64(fields[2]),
                      pid != ProcessInfo.processInfo.processIdentifier else { return nil }
                let command = String(fields[3])
                let name = URL(fileURLWithPath: command).lastPathComponent
                guard !name.isEmpty else { return nil }
                return ProcessMetric(pid: pid, name: name, cpuUsage: cpu, memoryBytes: rssKB * 1_024, path: command)
            }
            .sorted { $0.cpuUsage > $1.cpuUsage }
            .prefix(limit)
            .map { $0 }
        } catch {
            return []
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
