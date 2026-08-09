import Foundation
import VitalsCore

/// One calendar day of AI usage, scanned from local session metadata.
struct DailyUsage: Identifiable, Equatable {
    var day: Date
    var codex: UsageSummary
    var claude: UsageSummary

    var id: Date { day }
    var totalTokens: UInt64 { codex.totalTokens &+ claude.totalTokens }
}

@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot
    @Published private(set) var usage: AIUsageSnapshot
    /// Last 7 days including today (oldest first). Past days scan once and cache.
    @Published private(set) var usageDays: [DailyUsage] = []
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
    private var lastUsageDaysScan = Date.distantPast
    private var usageDaysScanInFlight = false
    private let demoMode: Bool

    var isDemo: Bool { demoMode }

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
            seedDemoUsageDays()
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
        var upload: [Double]
        var barCount: Int
        var barDuration: TimeInterval
        var range: HistoryTimeRange
        /// Effective window used for bucketing (may be shorter than `range` while history fills).
        var windowDuration: TimeInterval
        /// Wall-clock end of the window (the newest bucket's trailing edge).
        var windowEnd: Date
    }

    /// One grid for CPU / memory / swap / network so new bars emerge together.
    /// Zooms the window to retained history while samples are still filling the selected range.
    func overviewBarFrame(count: Int, range: HistoryTimeRange? = nil, now: Date = Date()) -> OverviewBarFrame {
        let resolved = range ?? historyRange
        let span = cpuHistory.availableSpan(range: resolved, now: now)
        let grid = BarTimeGrid.aligned(range: resolved, count: count, now: now, availableSpan: span)
        return OverviewBarFrame(
            cpu: grid.averages(from: cpuHistory),
            memory: grid.averages(from: memoryHistory),
            swap: grid.averages(from: swapHistory),
            download: grid.averages(from: downloadHistory),
            upload: grid.averages(from: uploadHistory),
            barCount: grid.bucketCount,
            barDuration: grid.bucketWidth,
            range: resolved,
            windowDuration: grid.bucketWidth * Double(grid.bucketCount),
            windowEnd: grid.bucketEnd(at: grid.bucketCount - 1)
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

    /// Settings can enable alerts after monitoring has already started. Ask
    /// for notification authorization at that point instead of requiring an
    /// app restart before alerts become capable of firing.
    func configureAlerts(enabled: Bool) {
        Task { await alerts.prepareIfNeeded(enabled: enabled) }
    }

    func refreshNow() {
        guard !demoMode else { return }
        Task { await refresh(forceUsage: true) }
    }

    func setHistoryRange(_ range: HistoryTimeRange) {
        historyRange = range
        settings.historyRange = range
    }

    /// Scan the previous six days of AI usage off the main actor. Past days
    /// are immutable, so one scan per app-day is enough; today's entry tracks
    /// the live `usage` snapshot.
    func refreshUsageDaysIfNeeded(now: Date = Date()) {
        guard !demoMode else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let scanIsFresh = usageDays.count == 7
            && usageDays.last?.day == today
            && now.timeIntervalSince(lastUsageDaysScan) < 6 * 3_600
        if scanIsFresh {
            syncTodayUsageDay()
            return
        }
        guard !usageDaysScanInFlight else { return }
        usageDaysScanInFlight = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task { [weak self] in
            let pastDays: [DailyUsage] = await Task.detached(priority: .utility) {
                (1...6).reversed().compactMap { offset -> DailyUsage? in
                    guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                    return DailyUsage(
                        day: day,
                        codex: AIUsageScanner.scanCodex(
                            root: home.appendingPathComponent(".codex", isDirectory: true),
                            on: day,
                            calendar: calendar
                        ),
                        claude: AIUsageScanner.scanClaude(
                            root: home.appendingPathComponent(".claude", isDirectory: true),
                            on: day,
                            calendar: calendar
                        )
                    )
                }
            }.value
            guard let self else { return }
            self.usageDays = pastDays + [DailyUsage(day: today, codex: self.usage.codex, claude: self.usage.claude)]
            self.lastUsageDaysScan = now
            self.usageDaysScanInFlight = false
        }
    }

    private func syncTodayUsageDay() {
        guard let last = usageDays.last else { return }
        let updated = DailyUsage(day: last.day, codex: usage.codex, claude: usage.claude)
        if updated != last {
            usageDays[usageDays.count - 1] = updated
        }
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
            syncTodayUsageDay()
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
        // Align with wall-clock "now" so overview bar grids (which bucket by Date()) are dense.
        let end = Date()
        // ~1h of samples at 20s — enough texture for 56 overview bars and strip sparklines.
        let spacing: TimeInterval = 20
        cpuHistory.replaceAll(Self.demoSeries(seed: 0.36, amplitude: 0.22, min: 0.05, max: 0.92), spacing: spacing, endingAt: end)
        memoryHistory.replaceAll(Self.demoSeries(seed: 0.55, amplitude: 0.08, min: 0.35, max: 0.88), spacing: spacing, endingAt: end)
        swapHistory.replaceAll(Self.demoSeries(seed: 0.04, amplitude: 0.025, min: 0, max: 0.2), spacing: spacing, endingAt: end)
        downloadHistory.replaceAll(
            Self.demoSeries(seed: 1_200_000, amplitude: 1_100_000, min: 40_000, max: 4_500_000),
            spacing: spacing,
            endingAt: end
        )
        uploadHistory.replaceAll(
            Self.demoSeries(seed: 220_000, amplitude: 180_000, min: 8_000, max: 1_200_000),
            spacing: spacing,
            endingAt: end
        )
        batteryHistory.replaceAll(Self.demoSeries(seed: 0.78, amplitude: 0.04, min: 0.55, max: 0.95), spacing: spacing, endingAt: end)
        // Disk fill is nearly constant in real life; keep the demo honest.
        diskHistory.replaceAll(Self.demoSeries(seed: 0.4145, amplitude: 0.0004, min: 0.4135, max: 0.4155), spacing: spacing, endingAt: end)
        thermalHistory.replaceAll(Self.demoSeries(seed: 0.15, amplitude: 0.05, min: 0, max: 0.6), spacing: spacing, endingAt: end)
    }

    private static func demoSeries(
        seed: Double,
        amplitude: Double,
        min: Double = 0.04,
        max: Double = 0.94,
        count: Int = 180
    ) -> [Double] {
        (0..<count).map { index in
            let wave = sin(Double(index) * 0.28) * amplitude
            let detail = sin(Double(index) * 0.91) * amplitude * 0.35
            let spike = (index % 23 == 0) ? amplitude * 0.55 : 0
            return Swift.min(Swift.max(seed + wave + detail + spike, min), max)
        }
    }

    private func seedDemoUsageDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Codex/Claude token totals for the six days before today (oldest first).
        let seeds: [(codex: UInt64, claude: UInt64, codexSessions: Int, claudeSessions: Int)] = [
            (198_400, 84_200, 5, 2),
            (512_800, 233_100, 9, 6),
            (301_500, 154_800, 6, 4),
            (48_200, 0, 2, 0),
            (0, 0, 0, 0),
            (422_600, 187_300, 8, 5),
        ]
        var days: [DailyUsage] = []
        for (offset, seed) in zip((1...6).reversed(), seeds) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            days.append(DailyUsage(
                day: day,
                codex: UsageSummary(
                    inputTokens: seed.codex / 2,
                    outputTokens: seed.codex / 10,
                    cachedTokens: seed.codex - seed.codex / 2 - seed.codex / 10,
                    totalTokens: seed.codex,
                    sessions: seed.codexSessions,
                    isAvailable: true
                ),
                claude: UsageSummary(
                    inputTokens: seed.claude / 2,
                    outputTokens: seed.claude / 10,
                    cachedTokens: seed.claude - seed.claude / 2 - seed.claude / 10,
                    totalTokens: seed.claude,
                    sessions: seed.claudeSessions,
                    isAvailable: true
                )
            ))
        }
        days.append(DailyUsage(day: today, codex: usage.codex, claude: usage.claude))
        usageDays = days
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
