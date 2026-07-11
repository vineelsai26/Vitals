import AppKit
import SwiftUI
import VitalsCore
import VKit

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case aiUsage = "AI Usage"
    case processes = "Processes"
    case network = "Network"
    case storage = "Storage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .aiUsage: return "brain.head.profile"
        case .processes: return "list.bullet.rectangle"
        case .network: return "network"
        case .storage: return "internaldrive"
        }
    }

    var shortcutKey: KeyEquivalent? {
        switch self {
        case .overview: return "1"
        case .aiUsage: return "2"
        case .processes: return "3"
        case .network: return "4"
        case .storage: return "5"
        }
    }
}

struct ContentView: View {
    @State private var selection: DashboardSection = .overview

    var body: some View {
        MainAppLayout(
            selection: $selection,
            scrollsContent: true,
            showsPreviewTrafficLights: false
        )
    }
}

struct MainAppLayout: View {
    @EnvironmentObject private var controller: MonitorController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: DashboardSection
    let scrollsContent: Bool
    let showsPreviewTrafficLights: Bool

    init(
        selection: Binding<DashboardSection>,
        scrollsContent: Bool,
        showsPreviewTrafficLights: Bool
    ) {
        _selection = selection
        self.scrollsContent = scrollsContent
        self.showsPreviewTrafficLights = showsPreviewTrafficLights
    }

    private var showsRangeControl: Bool {
        [.overview, .network, .storage].contains(selection)
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection, showsPreviewTrafficLights: showsPreviewTrafficLights)
                .frame(width: 150)
                .frame(maxHeight: .infinity)
            Divider().opacity(colorScheme == .dark ? 0.25 : 0.65)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .focusable()
        .onKeyPress(keys: [.init("1"), .init("2"), .init("3"), .init("4"), .init("5")]) { press in
            switch press.characters {
            case "1": selection = .overview
            case "2": selection = .aiUsage
            case "3": selection = .processes
            case "4": selection = .network
            case "5": selection = .storage
            default: return .ignored
            }
            return .handled
        }
    }

    @ViewBuilder private var detail: some View {
        // Overview fills the window; other sections scroll if needed.
        let fillsHeight = selection == .overview
        let content = VStack(alignment: .leading, spacing: fillsHeight ? 8 : 14) {
            pageHeader
            if let error = controller.errorMessage {
                StatusBanner(message: error, isError: true)
            }
            switch selection {
            case .overview:
                ParticleFlowOverview(onOpenProcesses: { selection = .processes })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .aiUsage:
                AIUsageDetailView()
            case .processes:
                ProcessesDetailView()
            case .network:
                NetworkDetailView()
            case .storage:
                StorageDetailView()
            }
        }
        .padding(.horizontal, fillsHeight ? 14 : 22)
        .padding(.vertical, fillsHeight ? 10 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fillsHeight ? .top : .topLeading)

        if scrollsContent && !fillsHeight {
            ScrollView { content }
        } else {
            content
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            Text(selection.rawValue)
                .font(VText.pageTitle)
            Spacer()
            if showsRangeControl {
                TimeRangeControl(selection: Binding(
                    get: { controller.historyRange },
                    set: { controller.setHistoryRange($0) }
                ))
            }
        }
        .frame(height: 34)
    }
}

private struct Sidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: DashboardSection
    let showsPreviewTrafficLights: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if showsPreviewTrafficLights {
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 0.98, green: 0.28, blue: 0.25))
                        Circle().fill(Color(red: 0.98, green: 0.66, blue: 0.16))
                        Circle().fill(Color(red: 0.20, green: 0.72, blue: 0.28))
                    }
                    .frame(width: 50)
                    .frame(height: 12)
                } else {
                    Color.clear.frame(width: 50, height: 12)
                }
            }
            .frame(height: 42)
            .padding(.horizontal, 18)

            ForEach(DashboardSection.allCases) { section in
                sidebarButton(for: section)
            }

            Spacer(minLength: 8)

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 16)
                    Text("Settings")
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(height: 30)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help("Open Settings (Command-comma)")

            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Palette.accent)
                Text("Vitals").font(VText.captionStrong)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(sidebarBackground)
    }

    private func sidebarButton(for section: DashboardSection) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            .foregroundStyle(selection == section ? selectedForeground : Color.primary.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selection == section ? selectedBackground : .clear, in: RoundedRectangle(cornerRadius: VRadius.chip))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityLabel(section.rawValue)
        .help(section.rawValue)
    }

    private var selectedBackground: Color {
        Palette.accent.opacity(colorScheme == .dark ? 0.16 : 0.09)
    }

    private var selectedForeground: Color {
        Palette.accent
    }

    private var sidebarBackground: Color {
        Palette.surface.opacity(0.035)
    }
}

struct TimeRangeControl: View {
    @Binding var selection: HistoryTimeRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryTimeRange.allCases) { range in
                let isSelected = selection == range
                Button {
                    selection = range
                } label: {
                    Text(range.label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.accent : Color.secondary)
                        .frame(width: 36, height: 24)
                        .background(
                            isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                            in: RoundedRectangle(cornerRadius: VRadius.control)
                        )
                }
                .buttonStyle(.plain)
                .help("Show \(range.label) of retained samples")
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: VRadius.control + 2))
    }
}

// MARK: - Network

private struct NetworkDetailView: View {
    @EnvironmentObject private var controller: MonitorController

    private var rateCeiling: Double {
        RateScale.ceiling(for: max(
            controller.downloadValues().max() ?? 0,
            controller.uploadValues().max() ?? 0,
            controller.snapshot.downloadBytesPerSecond,
            controller.snapshot.uploadBytesPerSecond
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCard {
                HStack(alignment: .top, spacing: 18) {
                    heroStat(
                        label: "Download",
                        value: VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond),
                        tint: VitalsColor.networkText
                    )
                    heroStat(
                        label: "Upload",
                        value: VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond),
                        tint: VitalsColor.uploadText
                    )
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(controller.snapshot.primaryInterfaceName.map { "Primary \($0)" } ?? "No primary interface")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                        Sparkline(
                            values: controller.downloadValues(),
                            tint: VitalsColor.network,
                            scale: .rate(ceiling: rateCeiling),
                            fill: true
                        )
                        .frame(width: 220, height: 34)
                    }
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Interfaces").font(VText.bodyStrong)
                    if controller.snapshot.networkInterfaces.isEmpty {
                        Text("No active interfaces reported yet.")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(controller.snapshot.networkInterfaces.enumerated()), id: \.element.id) { index, iface in
                            HStack {
                                Text(iface.name)
                                    .font(iface.isPrimary ? VText.bodyStrong : VText.body)
                                if iface.isPrimary {
                                    Text("Primary")
                                        .font(VText.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Spacer()
                                Text("↓ \(VitalsFormat.rate(iface.downloadBytesPerSecond))")
                                    .foregroundStyle(VitalsColor.networkText)
                                    .monospacedDigit()
                                Text("↑ \(VitalsFormat.rate(iface.uploadBytesPerSecond))")
                                    .foregroundStyle(VitalsColor.uploadText)
                                    .monospacedDigit()
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .font(VText.caption)
                            if index < controller.snapshot.networkInterfaces.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Throughput (\(controller.rangeDisplayLabel()))")
                            .font(VText.bodyStrong)
                        Spacer()
                        legend("Download", VitalsColor.network)
                        legend("Upload", VitalsColor.upload)
                    }
                    HStack(alignment: .top, spacing: 7) {
                        VStack(alignment: .trailing) {
                            Text(VitalsFormat.rate(rateCeiling))
                            Spacer()
                            Text(VitalsFormat.rate(rateCeiling / 2))
                            Spacer()
                            Text("0")
                        }
                        .font(VText.micro)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        MultiLineChart(
                            series: [
                                (controller.downloadValues(), VitalsColor.network, .rate),
                                (controller.uploadValues(), VitalsColor.upload, .rate),
                            ],
                            rateCeiling: rateCeiling
                        )
                        .frame(minHeight: 140, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    HStack {
                        ForEach(Array(controller.timeAxisLabels().enumerated()), id: \.offset) { index, date in
                            if index > 0 { Spacer() }
                            Text(VitalsFormat.axisTime(date, span: controller.historyRange.duration))
                        }
                    }
                    .font(VText.micro)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 63)
                    Text("Shared scale · both series plotted 0–\(VitalsFormat.rate(rateCeiling))")
                        .font(VText.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func heroStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).kicker()
            Text(value)
                .font(VText.metricL)
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(VText.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Storage

private struct VolumeInfo: Identifiable {
    let name: String
    let totalBytes: UInt64
    let availableBytes: UInt64
    let isInternal: Bool

    var id: String { name }
    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static let demoVolumes: [VolumeInfo] = [
        VolumeInfo(name: "Macintosh HD", totalBytes: 994_662_584_320, availableBytes: 582_345_723_904, isInternal: true),
        VolumeInfo(name: "Media", totalBytes: 4_000_787_030_016, availableBytes: 1_820_000_000_000, isInternal: false),
    ]

    static func mounted() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                totalBytes: UInt64(total),
                availableBytes: UInt64(values.volumeAvailableCapacity ?? 0),
                isInternal: values.volumeIsInternal ?? false
            )
        }
    }
}

private struct StorageDetailView: View {
    @EnvironmentObject private var controller: MonitorController
    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(controller.snapshot.diskVolumeName).font(VText.bodyStrong)
                        Spacer()
                        Text("Startup volume")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(VitalsFormat.percent(controller.snapshot.diskFraction))
                            .font(VText.metricL)
                            .foregroundStyle(VitalsColor.diskText)
                            .monospacedDigit()
                        Text("used")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                    }
                    capacityBar(fraction: controller.snapshot.diskFraction, tint: VitalsColor.disk)
                        .frame(height: 10)
                    HStack {
                        Text("\(VitalsFormat.bytes(controller.snapshot.diskUsedBytes)) used")
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(VitalsFormat.bytes(controller.snapshot.diskFreeBytes)) free")
                        Spacer()
                        Text("\(VitalsFormat.bytes(controller.snapshot.diskTotalBytes)) total")
                    }
                    .font(VText.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mounted volumes").font(VText.bodyStrong)
                    if volumes.isEmpty {
                        Text("No volumes reported.")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(volumes.enumerated()), id: \.element.id) { index, volume in
                            volumeRow(volume)
                            if index < volumes.count - 1 { Divider() }
                        }
                    }
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Fill over time (\(controller.rangeDisplayLabel()))").font(VText.bodyStrong)
                        Spacer()
                        Text(fillDelta)
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Sparkline(values: controller.diskValues(), tint: VitalsColor.disk, scale: .unit, fill: true)
                        .frame(height: 150)
                        .overlay(alignment: .topTrailing) {
                            Text("0–100% of capacity")
                                .font(VText.micro)
                                .foregroundStyle(.secondary)
                        }
                    Text("Disk fill uses an absolute scale. Growth is typically slow, so a flat line is the healthy shape.")
                        .font(VText.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            volumes = controller.isDemo ? VolumeInfo.demoVolumes : VolumeInfo.mounted()
        }
    }

    private var fillDelta: String {
        let values = controller.diskValues()
        guard let first = values.first, let last = values.last, controller.snapshot.diskTotalBytes > 0 else {
            return "No samples yet"
        }
        let deltaBytes = (last - first) * Double(controller.snapshot.diskTotalBytes)
        let threshold: Double = 500_000_000
        if abs(deltaBytes) < threshold {
            return "Effectively flat this \(controller.rangeDisplayLabel())"
        }
        let magnitude = VitalsFormat.bytes(UInt64(abs(deltaBytes)))
        return "\(deltaBytes > 0 ? "+" : "−")\(magnitude) this \(controller.rangeDisplayLabel())"
    }

    private func capacityBar(fraction: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
    }

    private func volumeRow(_ volume: VolumeInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name).font(VText.body)
                    if !volume.isInternal {
                        Text("External")
                            .font(VText.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Text("\(VitalsFormat.bytes(volume.usedBytes)) of \(VitalsFormat.bytes(volume.totalBytes))")
                        .font(VText.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                capacityBar(fraction: volume.usedFraction, tint: VitalsColor.disk)
                    .frame(height: 5)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AI Usage

private struct AIUsageDetailView: View {
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(VText.bodyStrong)
                        Spacer()
                        Text("Local session metadata")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        stat("Total tokens", VitalsFormat.compactTokens(controller.usage.totalTokens))
                        stat("Sessions", "\(controller.usage.totalSessions)")
                        stat(
                            "Last activity",
                            [controller.usage.codex.lastActivity, controller.usage.claude.lastActivity]
                                .compactMap { $0 }
                                .max()
                                .map(VitalsFormat.shortTime) ?? "—"
                        )
                    }
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Last 7 days").font(VText.bodyStrong)
                        Spacer()
                        legendDot("Codex", VitalsColor.codex)
                        legendDot("Claude", VitalsColor.claude)
                    }
                    if controller.usageDays.isEmpty {
                        Text("Scanning session history…")
                            .font(VText.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    } else {
                        DailyUsageBars(days: controller.usageDays)
                            .frame(minHeight: 120, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: 12) {
                providerCard("Codex", summary: controller.usage.codex, tint: VitalsColor.codex, textTint: VitalsColor.codexText)
                providerCard("Claude", summary: controller.usage.claude, tint: VitalsColor.claude, textTint: VitalsColor.claudeText)
            }
            Text("Totals include input, output, and cached tokens reported by each provider. Vitals never opens credential files or sends usage data anywhere.")
                .font(VText.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            controller.refreshUsageDaysIfNeeded()
        }
    }

    private func providerCard(_ title: String, summary: UsageSummary, tint: Color, textTint: Color) -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(title).font(VText.bodyStrong)
                    Spacer()
                    if let status = summary.displayStatus {
                        Text(status).font(VText.caption).foregroundStyle(.secondary)
                    }
                }
                Text(VitalsFormat.compactTokens(summary.totalTokens))
                    .font(VText.metricL)
                    .foregroundStyle(textTint)
                    .monospacedDigit()
                TokenSplitBar(summary: summary, tint: tint)
                    .frame(height: 6)
                HStack(spacing: 10) {
                    splitLegend("Input", VitalsFormat.compactTokens(summary.inputTokens), tint.opacity(0.95))
                    splitLegend("Output", VitalsFormat.compactTokens(summary.outputTokens), tint.opacity(0.55))
                    splitLegend("Cached", VitalsFormat.compactTokens(summary.cachedTokens), tint.opacity(0.28))
                    Spacer(minLength: 0)
                }
                HStack {
                    Text("\(summary.sessions) sessions")
                    Spacer()
                    if let last = summary.lastActivity {
                        Text("Last \(VitalsFormat.shortTime(last))")
                    }
                }
                .font(VText.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private func splitLegend(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(VText.caption)
        .lineLimit(1)
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(VText.caption).foregroundStyle(.secondary)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(VText.caption).foregroundStyle(.secondary)
            Text(value).font(VText.metricM).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Seven day columns, Codex and Claude stacked, absolute shared token scale.
private struct DailyUsageBars: View {
    let days: [DailyUsage]

    var body: some View {
        let peak = max(days.map(\.totalTokens).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Text("peak \(VitalsFormat.compactTokens(peak))")
                    .font(VText.micro)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    dayColumn(day, peak: peak)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func dayColumn(_ day: DailyUsage, peak: UInt64) -> some View {
        let isToday = Calendar.current.isDateInToday(day.day)
        return VStack(spacing: 5) {
            GeometryReader { geo in
                let codexH = geo.size.height * CGFloat(Double(day.codex.totalTokens) / Double(peak))
                let claudeH = geo.size.height * CGFloat(Double(day.claude.totalTokens) / Double(peak))
                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    if day.totalTokens == 0 {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 2)
                    } else {
                        if claudeH >= 0.5 {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(VitalsColor.claude.opacity(isToday ? 1 : 0.75))
                                .frame(height: max(claudeH, day.claude.totalTokens > 0 ? 2 : 0))
                        }
                        if codexH >= 0.5 {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(VitalsColor.codex.opacity(isToday ? 1 : 0.75))
                                .frame(height: max(codexH, day.codex.totalTokens > 0 ? 2 : 0))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            Text(dayLabel(day.day, isToday: isToday))
                .font(VText.caption)
                .foregroundStyle(isToday ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help(helpText(day))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText(day))
    }

    private func dayLabel(_ day: Date, isToday: Bool) -> String {
        isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated))
    }

    private func helpText(_ day: DailyUsage) -> String {
        let name = day.day.formatted(.dateTime.weekday(.wide).month().day())
        guard day.totalTokens > 0 else { return "\(name): no usage" }
        return "\(name): \(VitalsFormat.compactTokens(day.totalTokens)) tokens — Codex \(VitalsFormat.compactTokens(day.codex.totalTokens)), Claude \(VitalsFormat.compactTokens(day.claude.totalTokens))"
    }
}

/// Input / output / cached shares of one provider's total.
private struct TokenSplitBar: View {
    let summary: UsageSummary
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            // Providers disagree on whether cached tokens count into the
            // total, so shares are of the component sum — never overflows.
            let total = max(Double(summary.inputTokens &+ summary.outputTokens &+ summary.cachedTokens), 1)
            HStack(spacing: 1) {
                segment(width: geo.size.width * CGFloat(Double(summary.inputTokens) / total), opacity: 0.95)
                segment(width: geo.size.width * CGFloat(Double(summary.outputTokens) / total), opacity: 0.55)
                segment(width: geo.size.width * CGFloat(Double(summary.cachedTokens) / total), opacity: 0.28)
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder private func segment(width: CGFloat, opacity: Double) -> some View {
        if width >= 0.5 {
            Rectangle().fill(tint.opacity(opacity)).frame(width: width)
        }
    }
}

// MARK: - Processes

private struct ProcessesDetailView: View {
    @EnvironmentObject private var controller: MonitorController
    @State private var searchText = ""
    @State private var hoveredPID: Int32?

    private var visibleProcesses: [ProcessMetric] {
        guard !searchText.isEmpty else { return controller.sortedProcesses }
        return controller.sortedProcesses.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            String($0.pid).contains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                searchField
                sortControl
                Spacer()
                Text(scopeLabel)
                    .font(VText.caption)
                    .foregroundStyle(.secondary)
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU").frame(width: 70, alignment: .trailing)
                        Text("Memory").frame(width: 84, alignment: .trailing)
                    }
                    .font(VText.captionStrong)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    ForEach(Array(visibleProcesses.enumerated()), id: \.element.id) { index, process in
                        processRow(process)
                        if index < visibleProcesses.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }

                    if visibleProcesses.isEmpty {
                        Text(emptyMessage)
                            .font(VText.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var scopeLabel: String {
        if searchText.isEmpty {
            return "Top \(controller.sortedProcesses.count) by \(controller.processSort.label) · ranked sample"
        }
        return "\(visibleProcesses.count) of top \(controller.sortedProcesses.count)"
    }

    private var emptyMessage: String {
        if controller.sortedProcesses.isEmpty {
            return "Waiting for process sample…"
        }
        return "No matches in the top \(controller.snapshot.topProcessLimit) sample. Vitals ranks the busiest processes, not every process."
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter top \(controller.snapshot.topProcessLimit)", text: $searchText)
                .textFieldStyle(.plain)
                .font(VText.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 240, height: 26)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: VRadius.control + 2))
    }

    private var sortControl: some View {
        HStack(spacing: 2) {
            ForEach(ProcessSort.allCases) { sort in
                let isSelected = controller.processSort == sort
                Button {
                    controller.processSort = sort
                } label: {
                    Text(sort.label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.accent : Color.secondary)
                        .frame(width: 64, height: 20)
                        .background(
                            isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                            in: RoundedRectangle(cornerRadius: VRadius.control)
                        )
                }
                .buttonStyle(.plain)
                .help("Sort by \(sort.label)")
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: VRadius.control + 2))
    }

    private func processRow(_ process: ProcessMetric) -> some View {
        HStack {
            HStack(spacing: 8) {
                processIcon(process)
                Text(process.name)
                    .lineLimit(1)
                    .help("\(process.name) · PID \(process.pid)\(process.path.map { "\n\($0)" } ?? "")")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%%", process.cpuUsage))
                .frame(width: 70, alignment: .trailing)
                .monospacedDigit()
            Text(VitalsFormat.bytes(process.memoryBytes))
                .frame(width: 84, alignment: .trailing)
                .monospacedDigit()
        }
        .font(VText.body)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            hoveredPID == process.pid ? Color.primary.opacity(0.045) : Color.clear,
            in: RoundedRectangle(cornerRadius: VRadius.control)
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredPID = hovering ? process.pid : (hoveredPID == process.pid ? nil : hoveredPID)
        }
        .contextMenu {
            Button("Copy PID \(process.pid)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(process.pid)", forType: .string)
            }
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(process.name, forType: .string)
            }
            if let path = process.path {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
        }
    }

    @ViewBuilder private func processIcon(_ process: ProcessMetric) -> some View {
        if let icon = ProcessIconLookup.icon(for: process) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 10))
                .frame(width: 16, height: 16)
        }
    }
}

enum ProcessIconLookup {
    private static let cache = NSCache<NSNumber, NSImage>()

    static func icon(for process: ProcessMetric) -> NSImage? {
        let key = NSNumber(value: process.pid)
        if let cached = cache.object(forKey: key) { return cached }
        let icon: NSImage?
        if let path = process.path {
            let url = URL(fileURLWithPath: path)
            var appURL = url
            while appURL.pathExtension != "app", appURL.path != "/" {
                appURL.deleteLastPathComponent()
            }
            if appURL.pathExtension == "app" {
                icon = NSWorkspace.shared.icon(forFile: appURL.path)
                if let icon { cache.setObject(icon, forKey: key) }
                return icon
            }
        }
        let normalized = process.name.lowercased()
        icon = NSWorkspace.shared.runningApplications.first {
            ($0.localizedName?.lowercased()).map { $0 == normalized || $0.contains(normalized) } ?? false
        }?.icon
        if let icon { cache.setObject(icon, forKey: key) }
        return icon
    }
}
