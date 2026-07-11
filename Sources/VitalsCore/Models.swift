import Foundation

public enum ThermalLevel: String, Sendable, Codable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    public var label: String { rawValue.capitalized }

    public var isElevated: Bool {
        self == .serious || self == .critical
    }
}

public enum HardwareMetricAvailability: String, Sendable, Codable {
    case detected
    case unavailable
}

/// Vitals currently reports physical-memory occupancy, not macOS's private
/// memory-pressure gauge. Keep the distinction explicit so high cache usage is
/// never presented as a pressure diagnosis.
public enum MemoryStatus: String, Sendable, Codable, Equatable {
    case usageOnly

    public var label: String { "Memory used" }
    public var isPressureDiagnosis: Bool { false }
}

public enum BatteryPowerState: String, Sendable, Codable, Equatable {
    case noBattery
    case onBattery
    case charging
    case chargedOnAC

    public var label: String {
        switch self {
        case .noBattery: return "AC Power"
        case .onBattery: return "On Battery"
        case .charging: return "Charging"
        case .chargedOnAC: return "On AC (Full)"
        }
    }
}

public struct ProcessMetric: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var cpuUsage: Double
    public var memoryBytes: UInt64
    public var path: String?

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        cpuUsage: Double,
        memoryBytes: UInt64,
        path: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.cpuUsage = cpuUsage
        self.memoryBytes = memoryBytes
        self.path = path
    }
}

public struct NetworkInterfaceMetric: Sendable, Equatable, Identifiable {
    public var name: String
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double
    public var isPrimary: Bool

    public var id: String { name }

    public init(
        name: String,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        isPrimary: Bool
    ) {
        self.name = name
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.isPrimary = isPrimary
    }
}

/// Physical RAM + swap breakdown from host_statistics64 / vm.swapusage.
public struct MemoryBreakdown: Sendable, Equatable {
    public var totalBytes: UInt64
    public var wiredBytes: UInt64
    public var activeBytes: UInt64
    public var inactiveBytes: UInt64
    public var compressedBytes: UInt64
    public var freeBytes: UInt64
    public var speculativeBytes: UInt64
    public var purgeableBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64

    public init(
        totalBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        activeBytes: UInt64 = 0,
        inactiveBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        speculativeBytes: UInt64 = 0,
        purgeableBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0
    ) {
        self.totalBytes = totalBytes
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.speculativeBytes = speculativeBytes
        self.purgeableBytes = purgeableBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }

    /// App/file cache + app memory style “used” (wired + active + inactive + compressed).
    public var usedBytes: UInt64 {
        wiredBytes + activeBytes + inactiveBytes + compressedBytes
    }

    public var availableBytes: UInt64 {
        freeBytes + speculativeBytes
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    public var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(availableBytes) / Double(totalBytes), 0), 1)
    }

    /// Swap used relative to physical RAM (for chart scaling).
    public var swapFractionOfPhysical: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(swapUsedBytes) / Double(totalBytes), 0), 1)
    }

    public var swapFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return min(max(Double(swapUsedBytes) / Double(swapTotalBytes), 0), 1)
    }

    /// Segments for stacked bars as fractions of physical total (may not sum to 1).
    public var compositionSegments: [(name: String, fraction: Double)] {
        guard totalBytes > 0 else { return [] }
        let t = Double(totalBytes)
        return [
            ("Wired", Double(wiredBytes) / t),
            ("Active", Double(activeBytes) / t),
            ("Inactive", Double(inactiveBytes) / t),
            ("Compressed", Double(compressedBytes) / t),
            ("Free", Double(availableBytes) / t),
        ]
    }

    public static let demo = MemoryBreakdown(
        totalBytes: 34_359_738_368,
        wiredBytes: 4_294_967_296,
        activeBytes: 8_589_934_592,
        inactiveBytes: 3_221_225_472,
        compressedBytes: 2_684_354_560,
        freeBytes: 12_884_901_888,
        speculativeBytes: 536_870_912,
        purgeableBytes: 1_073_741_824,
        swapUsedBytes: 536_870_912,
        swapTotalBytes: 2_147_483_648
    )
}

public struct SystemSnapshot: Sendable, Equatable {
    public var capturedAt: Date
    public var cpuUsage: Double
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memory: MemoryBreakdown
    public var memoryStatus: MemoryStatus
    public var diskUsedBytes: UInt64
    public var diskTotalBytes: UInt64
    public var diskVolumeName: String
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double
    public var primaryInterfaceName: String?
    public var networkInterfaces: [NetworkInterfaceMetric]
    public var loadAverage: Double
    public var loadAverage5: Double
    public var loadAverage15: Double
    public var uptime: TimeInterval
    public var thermalLevel: ThermalLevel
    public var processorName: String
    public var processorCount: Int
    public var gpuName: String
    public var gpuAvailability: HardwareMetricAvailability
    public var neuralEngineName: String
    public var neuralEngineAvailability: HardwareMetricAvailability
    public var batteryLevel: Double?
    public var batteryPowerState: BatteryPowerState
    public var batteryTimeRemaining: TimeInterval?
    public var topProcesses: [ProcessMetric]
    /// Maximum number of processes requested from the collector. This is a
    /// ranked subset, not the total number of processes on the machine.
    public var topProcessLimit: Int

    public init(
        capturedAt: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsedBytes: UInt64 = 0,
        memoryTotalBytes: UInt64 = 0,
        memory: MemoryBreakdown = MemoryBreakdown(),
        memoryStatus: MemoryStatus = .usageOnly,
        diskUsedBytes: UInt64 = 0,
        diskTotalBytes: UInt64 = 0,
        diskVolumeName: String = "Macintosh HD",
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        primaryInterfaceName: String? = nil,
        networkInterfaces: [NetworkInterfaceMetric] = [],
        loadAverage: Double = 0,
        loadAverage5: Double = 0,
        loadAverage15: Double = 0,
        uptime: TimeInterval = 0,
        thermalLevel: ThermalLevel = .nominal,
        processorName: String = "Unknown processor",
        processorCount: Int = 0,
        gpuName: String = "GPU unavailable",
        gpuAvailability: HardwareMetricAvailability = .unavailable,
        neuralEngineName: String = "Neural Engine unavailable",
        neuralEngineAvailability: HardwareMetricAvailability = .unavailable,
        batteryLevel: Double? = nil,
        batteryPowerState: BatteryPowerState = .noBattery,
        batteryTimeRemaining: TimeInterval? = nil,
        topProcesses: [ProcessMetric] = [],
        topProcessLimit: Int = 25
    ) {
        self.capturedAt = capturedAt
        self.cpuUsage = cpuUsage
        // Prefer breakdown totals when provided so used/total stay consistent.
        let resolvedMemory: MemoryBreakdown
        if memory.totalBytes > 0 {
            resolvedMemory = memory
        } else if memoryTotalBytes > 0 {
            resolvedMemory = MemoryBreakdown(
                totalBytes: memoryTotalBytes,
                activeBytes: memoryUsedBytes,
                freeBytes: memoryTotalBytes > memoryUsedBytes ? memoryTotalBytes - memoryUsedBytes : 0
            )
        } else {
            resolvedMemory = memory
        }
        self.memory = resolvedMemory
        self.memoryStatus = memoryStatus
        self.memoryUsedBytes = resolvedMemory.usedBytes > 0 ? resolvedMemory.usedBytes : memoryUsedBytes
        self.memoryTotalBytes = resolvedMemory.totalBytes > 0 ? resolvedMemory.totalBytes : memoryTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskVolumeName = diskVolumeName
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.primaryInterfaceName = primaryInterfaceName
        self.networkInterfaces = networkInterfaces
        self.loadAverage = loadAverage
        self.loadAverage5 = loadAverage5
        self.loadAverage15 = loadAverage15
        self.uptime = uptime
        self.thermalLevel = thermalLevel
        self.processorName = processorName
        self.processorCount = processorCount
        self.gpuName = gpuName
        self.gpuAvailability = gpuAvailability
        self.neuralEngineName = neuralEngineName
        self.neuralEngineAvailability = neuralEngineAvailability
        self.batteryLevel = batteryLevel
        self.batteryPowerState = batteryPowerState
        self.batteryTimeRemaining = batteryTimeRemaining
        self.topProcesses = topProcesses
        self.topProcessLimit = topProcessLimit
    }

    public var memoryFraction: Double {
        memory.usedFraction
    }

    public var diskFraction: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(max(Double(diskUsedBytes) / Double(diskTotalBytes), 0), 1)
    }

    public var diskFreeBytes: UInt64 {
        diskTotalBytes > diskUsedBytes ? diskTotalBytes - diskUsedBytes : 0
    }

    public var processListLabel: String {
        "Top \(topProcessLimit) processes"
    }

    /// Matches Vitals' memory definition (active + inactive + wired + compressed).
    public static let memoryDefinitionNote =
        "Memory used includes wired, active, inactive, and compressed pages. Free includes free + speculative. Swap is separate from physical RAM."

    /// Demo snapshot for UI renders. `capturedAt` is "now" so history grids align with seeded series.
    public static var demo: SystemSnapshot {
        SystemSnapshot(
        capturedAt: Date(),
        cpuUsage: 0.37,
        memoryUsedBytes: MemoryBreakdown.demo.usedBytes,
        memoryTotalBytes: MemoryBreakdown.demo.totalBytes,
        memory: .demo,
        diskUsedBytes: 412_316_860_416,
        diskTotalBytes: 994_662_584_320,
        diskVolumeName: "Macintosh HD",
        downloadBytesPerSecond: 2_420_000,
        uploadBytesPerSecond: 184_000,
        primaryInterfaceName: "en0",
        networkInterfaces: [
            NetworkInterfaceMetric(name: "en0", downloadBytesPerSecond: 2_420_000, uploadBytesPerSecond: 184_000, isPrimary: true),
            NetworkInterfaceMetric(name: "awdl0", downloadBytesPerSecond: 1_200, uploadBytesPerSecond: 800, isPrimary: false),
        ],
        loadAverage: 2.14,
        loadAverage5: 1.88,
        loadAverage15: 1.52,
        uptime: 302_460,
        thermalLevel: .nominal,
        processorName: "Apple M4 Pro",
        processorCount: 14,
        gpuName: "Apple GPU",
        gpuAvailability: .detected,
        neuralEngineName: "Apple Neural Engine",
        neuralEngineAvailability: .detected,
        batteryLevel: 0.78,
        batteryPowerState: .onBattery,
        batteryTimeRemaining: 9_240,
        topProcesses: [
            ProcessMetric(pid: 1201, name: "Cursor", cpuUsage: 23.4, memoryBytes: 1_288_490_189, path: "/Applications/Cursor.app"),
            ProcessMetric(pid: 882, name: "Chrome", cpuUsage: 12.7, memoryBytes: 933_232_640, path: "/Applications/Google Chrome.app"),
            ProcessMetric(pid: 1440, name: "Code", cpuUsage: 8.6, memoryBytes: 536_870_912),
            ProcessMetric(pid: 932, name: "Notion", cpuUsage: 6.1, memoryBytes: 396_361_728),
            ProcessMetric(pid: 410, name: "Discord", cpuUsage: 4.2, memoryBytes: 268_435_456),
            ProcessMetric(pid: 501, name: "WindowServer", cpuUsage: 3.1, memoryBytes: 180_000_000),
            ProcessMetric(pid: 220, name: "kernel_task", cpuUsage: 2.4, memoryBytes: 90_000_000),
            ProcessMetric(pid: 330, name: "Finder", cpuUsage: 1.2, memoryBytes: 140_000_000),
        ]
        )
    }
}

public struct UsageSummary: Sendable, Equatable {
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var cachedTokens: UInt64
    public var totalTokens: UInt64
    public var sessions: Int
    public var lastActivity: Date?
    public var isAvailable: Bool
    public var statusMessage: String?

    public init(
        inputTokens: UInt64 = 0,
        outputTokens: UInt64 = 0,
        cachedTokens: UInt64 = 0,
        totalTokens: UInt64 = 0,
        sessions: Int = 0,
        lastActivity: Date? = nil,
        isAvailable: Bool = false,
        statusMessage: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.totalTokens = totalTokens
        self.sessions = sessions
        self.lastActivity = lastActivity
        self.isAvailable = isAvailable
        self.statusMessage = statusMessage
    }

    public var displayStatus: String? {
        if let statusMessage, !statusMessage.isEmpty { return statusMessage }
        if !isAvailable { return "Unavailable" }
        if totalTokens == 0 && sessions == 0 { return "No activity today" }
        return nil
    }
}

public struct AIUsageSnapshot: Sendable, Equatable {
    public var capturedAt: Date
    public var codex: UsageSummary
    public var claude: UsageSummary

    public init(capturedAt: Date = Date(), codex: UsageSummary, claude: UsageSummary) {
        self.capturedAt = capturedAt
        self.codex = codex
        self.claude = claude
    }

    public static let empty = AIUsageSnapshot(codex: UsageSummary(), claude: UsageSummary())

    public static let demo = AIUsageSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1_788_700_000),
        codex: UsageSummary(
            inputTokens: 112_500,
            outputTokens: 18_420,
            cachedTokens: 171_800,
            totalTokens: 302_720,
            sessions: 7,
            lastActivity: Date(timeIntervalSince1970: 1_788_699_820),
            isAvailable: true
        ),
        claude: UsageSummary(
            inputTokens: 96_200,
            outputTokens: 12_880,
            cachedTokens: 62_400,
            totalTokens: 171_480,
            sessions: 4,
            lastActivity: Date(timeIntervalSince1970: 1_788_699_400),
            isAvailable: true
        )
    )

    public var totalTokens: UInt64 { codex.totalTokens &+ claude.totalTokens }
    public var totalSessions: Int { codex.sessions + claude.sessions }
}

public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var nice: UInt64
    public var idle: UInt64

    public init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) {
        self.user = user
        self.system = system
        self.nice = nice
        self.idle = idle
    }

    public var total: UInt64 { user &+ system &+ nice &+ idle }

    public static func utilization(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total >= previous.total, current.idle >= previous.idle else { return 0 }
        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return 0 }
        let idleDelta = current.idle - previous.idle
        return min(max(1 - (Double(idleDelta) / Double(totalDelta)), 0), 1)
    }
}

public struct NetworkCounters: Sendable, Equatable {
    public var receivedBytes: UInt64
    public var sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }

    public static func rates(
        previous: NetworkCounters,
        current: NetworkCounters,
        elapsed: TimeInterval
    ) -> (download: Double, upload: Double) {
        guard elapsed > 0,
              current.receivedBytes >= previous.receivedBytes,
              current.sentBytes >= previous.sentBytes else { return (0, 0) }
        return (
            Double(current.receivedBytes - previous.receivedBytes) / elapsed,
            Double(current.sentBytes - previous.sentBytes) / elapsed
        )
    }
}

public enum ProcessSort: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory

    public var id: String { rawValue }
    public var label: String { rawValue == "cpu" ? "CPU" : "Memory" }
}
