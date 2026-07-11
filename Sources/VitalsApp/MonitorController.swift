import Foundation
import VitalsCore

@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot
    @Published private(set) var usage: AIUsageSnapshot
    @Published private(set) var cpuHistory = MetricHistory()
    @Published private(set) var memoryHistory = MetricHistory()
    @Published private(set) var swapHistory = MetricHistory()
    @Published private(set) var downloadHistory = MetricHistory()
    @Published private(set) var uploadHistory = MetricHistory()
    @Published private(set) var batteryHistory = MetricHistory()
    @Published private(set) var diskHistory = MetricHistory()
    @Published private(set) var thermalHistory = MetricHistory()
    @Published var historyRange: HistoryTimeRange
    @Published private(set) var isRunning = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var processSort: ProcessSort = .cpu

    private let systemSampler: SystemMetricsSampler
    private let usageScanner: AIUsageScanner
    private let settings: AppSettings
    private let alerts = AlertManager()
    private var samplingTask: Task<Void, Never>?
    private var lastUsageRefresh = Date.distantPast
    private let demoMode: Bool

    init(
        settings: AppSettings? = nil,
        systemSampler: SystemMetricsSampler = SystemMetricsSampler(),
        usageScanner: AIUsageScanner = AIUsageScanner(),
        snapshot: SystemSnapshot = SystemSnapshot(),
        usage: AIUsageSnapshot = .empty,
        demoMode: Bool = false
    ) {
        let resolved = settings ?? .shared
        self.settings = resolved
        self.systemSampler = systemSampler
        self.usageScanner = usageScanner
        self.snapshot = snapshot
        self.usage = usage
        self.historyRange = resolved.historyRange
        self.demoMode = demoMode
        self.isRunning = demoMode
        if demoMode {
            seedDemoHistories()
        }
    }

    deinit {
        samplingTask?.cancel()
    }

    var sortedProcesses: [ProcessMetric] {
        switch processSort {
        case .cpu:
            return snapshot.topProcesses.sorted { $0.cpuUsage > $1.cpuUsage }
        case .memory:
            return snapshot.topProcesses.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    func cpuValues(range: HistoryTimeRange? = nil) -> [Double] {
        cpuHistory.values(range: range ?? historyRange)
    }

    func memoryValues(range: HistoryTimeRange? = nil) -> [Double] {
        memoryHistory.values(range: range ?? historyRange)
    }

    /// Swap used as a fraction of physical RAM (same scale as memory bars).
    func swapValues(range: HistoryTimeRange? = nil) -> [Double] {
        swapHistory.values(range: range ?? historyRange)
    }

    func downloadValues(range: HistoryTimeRange? = nil) -> [Double] {
        downloadHistory.values(range: range ?? historyRange)
    }

    func uploadValues(range: HistoryTimeRange? = nil) -> [Double] {
        uploadHistory.values(range: range ?? historyRange)
    }

    func batteryValues(range: HistoryTimeRange? = nil) -> [Double] {
        batteryHistory.values(range: range ?? historyRange)
    }

    func diskValues(range: HistoryTimeRange? = nil) -> [Double] {
        diskHistory.values(range: range ?? historyRange)
    }

    func thermalValues(range: HistoryTimeRange? = nil) -> [Double] {
        thermalHistory.values(range: range ?? historyRange)
    }

    /// Shared wall-clock bar grid for all overview metrics (same bucket edges).
    struct OverviewBarFrame: Equatable {
        var cpu: [Double]
        var memory: [Double]
        var swap: [Double]
        var download: [Double]
        var barCount: Int
        var barDuration: TimeInterval
        var range: HistoryTimeRange
    }

    /// One grid for CPU / memory / swap / network so new bars emerge together.
    func overviewBarFrame(count: Int, range: HistoryTimeRange? = nil, now: Date = Date()) -> OverviewBarFrame {
        let resolved = range ?? historyRange
        let grid = BarTimeGrid.aligned(range: resolved, count: count, now: now)
        return OverviewBarFrame(
            cpu: grid.averages(from: cpuHistory),
            memory: grid.averages(from: memoryHistory),
            swap: grid.averages(from: swapHistory),
            download: grid.averages(from: downloadHistory),
            barCount: grid.bucketCount,
            barDuration: grid.bucketWidth,
            range: resolved
        )
    }

    func barDuration(count: Int, range: HistoryTimeRange? = nil) -> TimeInterval {
        BarTimeGrid.aligned(range: range ?? historyRange, count: count).bucketWidth
    }

    func timeAxisLabels(count: Int = 5) -> [Date] {
        cpuHistory.timeAxisLabels(range: historyRange, count: count)
    }

    func rangeDisplayLabel() -> String {
        cpuHistory.displayLabel(range: historyRange)
    }

    func start() {
        guard !demoMode, samplingTask == nil else { return }
        isRunning = true
        samplingTask = Task { [weak self] in
            await self?.alerts.prepareIfNeeded(enabled: self?.settings.alertsEnabled == true)
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let cadence = self.settings.refreshCadence.rawValue
                try? await Task.sleep(for: .seconds(cadence))
            }
        }
    }

    func pause() {
        samplingTask?.cancel()
        samplingTask = nil
        isRunning = false
    }

    func resume() {
        start()
    }

    func toggleRunning() {
        isRunning ? pause() : resume()
    }

    func refreshNow() {
        guard !demoMode else { return }
        Task { await refresh(forceUsage: true) }
    }

    func setHistoryRange(_ range: HistoryTimeRange) {
        historyRange = range
        settings.historyRange = range
    }

    private func refresh(forceUsage: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let newSnapshot = await systemSampler.sample()
        snapshot = newSnapshot
        let at = newSnapshot.capturedAt
        cpuHistory.append(newSnapshot.cpuUsage, at: at)
        memoryHistory.append(newSnapshot.memoryFraction, at: at)
        swapHistory.append(newSnapshot.memory.swapFractionOfPhysical, at: at)
        downloadHistory.append(newSnapshot.downloadBytesPerSecond, at: at)
        uploadHistory.append(newSnapshot.uploadBytesPerSecond, at: at)
        diskHistory.append(newSnapshot.diskFraction, at: at)
        thermalHistory.append(Self.thermalValue(newSnapshot.thermalLevel), at: at)
        if let batteryLevel = newSnapshot.batteryLevel {
            batteryHistory.append(batteryLevel, at: at)
        }

        if forceUsage || Date().timeIntervalSince(lastUsageRefresh) >= 30 {
            var newUsage = await usageScanner.scanToday()
            if !settings.codexUsageEnabled {
                newUsage.codex = UsageSummary(
                    isAvailable: false,
                    statusMessage: "Disabled in Settings"
                )
            }
            if !settings.claudeUsageEnabled {
                newUsage.claude = UsageSummary(
                    isAvailable: false,
                    statusMessage: "Disabled in Settings"
                )
            }
            usage = newUsage
            lastUsageRefresh = Date()
        }

        if settings.alertsEnabled {
            await alerts.prepareIfNeeded(enabled: true)
            alerts.evaluate(snapshot: newSnapshot, settings: settings)
        }
        errorMessage = nil
    }

    private static func thermalValue(_ level: ThermalLevel) -> Double {
        switch level {
        case .nominal: return 0.15
        case .fair: return 0.4
        case .serious: return 0.7
        case .critical: return 1.0
        }
    }

    private func seedDemoHistories() {
        let end = snapshot.capturedAt
        cpuHistory.replaceAll(Self.demoSeries(seed: 0.36, amplitude: 0.15), spacing: 30, endingAt: end)
        memoryHistory.replaceAll(Self.demoSeries(seed: 0.55, amplitude: 0.035), spacing: 30, endingAt: end)
        swapHistory.replaceAll(Self.demoSeries(seed: 0.04, amplitude: 0.02, min: 0, max: 0.25), spacing: 30, endingAt: end)
        downloadHistory.replaceAll(
            Self.demoSeries(seed: 800_000, amplitude: 400_000, min: 0, max: 5_000_000),
            spacing: 30,
            endingAt: end
        )
        uploadHistory.replaceAll(
            Self.demoSeries(seed: 120_000, amplitude: 80_000, min: 0, max: 2_000_000),
            spacing: 30,
            endingAt: end
        )
        batteryHistory.replaceAll(Self.demoSeries(seed: 0.78, amplitude: 0.018), spacing: 30, endingAt: end)
        diskHistory.replaceAll(Self.demoSeries(seed: 0.41, amplitude: 0.002), spacing: 30, endingAt: end)
        thermalHistory.replaceAll(Self.demoSeries(seed: 0.15, amplitude: 0.02), spacing: 30, endingAt: end)
    }

    private static func demoSeries(
        seed: Double,
        amplitude: Double,
        min: Double = 0.04,
        max: Double = 0.94,
        count: Int = 120
    ) -> [Double] {
        (0..<count).map { index in
            let wave = sin(Double(index) * 0.42) * amplitude
            let detail = sin(Double(index) * 1.37) * amplitude * 0.22
            return Swift.min(Swift.max(seed + wave + detail, min), max)
        }
    }

    static func demo(settings: AppSettings? = nil) -> MonitorController {
        MonitorController(
            settings: settings,
            snapshot: .demo,
            usage: .demo,
            demoMode: true
        )
    }
}
