import AppKit
import SwiftUI
import VitalsCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case aiUsage = "AI Usage"
    case processes = "Processes"
    case network = "Network"
    case storage = "Storage"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "house"
        case .aiUsage: return "brain.head.profile"
        case .processes: return "terminal"
        case .network: return "globe"
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
        .background(appBackground)
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
        let content = VStack(alignment: .leading, spacing: fillsHeight ? 10 : 14) {
            pageHeader
            if let error = controller.errorMessage {
                StatusBanner(message: error, isError: true)
            }
            switch selection {
            case .overview:
                OverviewDashboard()
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
        .padding(.horizontal, fillsHeight ? 16 : 22)
        .padding(.vertical, fillsHeight ? 12 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fillsHeight ? .top : .topLeading)

        if scrollsContent && !fillsHeight {
            ScrollView { content }
        } else {
            content
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.rawValue)
                    .font(.system(size: 18, weight: .semibold))
                if selection == .overview {
                    Text(controller.snapshot.processorName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selection == .overview {
                TimeRangeControl(selection: Binding(
                    get: { controller.historyRange },
                    set: { controller.setHistoryRange($0) }
                ))
            }
            Button {
                settings.appearance.cycle()
            } label: {
                Image(systemName: settings.appearance.toggleSymbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 26)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(settings.appearance.toggleHelp)
        }
        .frame(height: 34)
    }

    private var appBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.025, green: 0.037, blue: 0.055)
            : Color(red: 0.985, green: 0.988, blue: 0.995)
    }
}

private struct Sidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
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

            Button {
                openSettings()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 15)
                    Text("Settings")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.82))
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .help("Open Settings (Command-comma)")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(VitalsColor.cpu)
                Text("Vitals").font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15)
                Text(section.rawValue)
                    .font(.system(size: 11, weight: selection == section ? .medium : .regular))
                Spacer()
            }
            .foregroundStyle(selection == section ? selectedForeground : Color.primary.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selection == section ? selectedBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityLabel(section.rawValue)
        .help(section.rawValue)
    }

    private var selectedBackground: Color {
        colorScheme == .dark ? .white.opacity(0.095) : VitalsColor.cpu.opacity(0.09)
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? .white : VitalsColor.cpu
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.035, green: 0.05, blue: 0.073)
            : Color(red: 0.97, green: 0.976, blue: 0.99)
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
                        .foregroundStyle(isSelected ? VitalsColor.cpu : Color.secondary)
                        .frame(width: 36, height: 24)
                        .background(
                            isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
                .help("Show \(range.label) of retained samples")
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct OverviewDashboard: View {
    var body: some View {
        ParticleFlowOverview()
    }
}

private struct NetworkDetailView: View {
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CompactMetricCard(
                    title: "Download",
                    value: VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond),
                    detailLabel: "Primary",
                    detailValue: controller.snapshot.primaryInterfaceName ?? "—",
                    history: controller.downloadValues(),
                    tint: VitalsColor.network
                )
                CompactMetricCard(
                    title: "Upload",
                    value: VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond),
                    detailLabel: "Primary",
                    detailValue: controller.snapshot.primaryInterfaceName ?? "—",
                    history: controller.uploadValues(),
                    tint: VitalsColor.upload
                )
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Interfaces").font(.system(size: 12, weight: .semibold))
                    if controller.snapshot.networkInterfaces.isEmpty {
                        Text("No active interfaces reported yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.snapshot.networkInterfaces) { iface in
                            HStack {
                                Text(iface.name)
                                    .font(.system(size: 11, weight: iface.isPrimary ? .semibold : .regular))
                                if iface.isPrimary {
                                    Text("Primary")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Spacer()
                                Text("↓ \(VitalsFormat.rate(iface.downloadBytesPerSecond))")
                                    .monospacedDigit()
                                Text("↑ \(VitalsFormat.rate(iface.uploadBytesPerSecond))")
                                    .monospacedDigit()
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .font(.system(size: 10.5))
                            if iface.id != controller.snapshot.networkInterfaces.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Throughput (\(controller.rangeDisplayLabel()))")
                        .font(.system(size: 12, weight: .semibold))
                    MultiLineChart(series: [
                        (controller.downloadValues(), VitalsColor.network, .rate),
                        (controller.uploadValues(), VitalsColor.upload, .rate),
                    ])
                    .frame(height: 160)
                    HStack {
                        legend("Download", VitalsColor.network)
                        legend("Upload", VitalsColor.upload)
                        Spacer()
                        Text("Shared scale · minimum 1 MB/s")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct StorageDetailView: View {
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CompactMetricCard(
                    title: controller.snapshot.diskVolumeName,
                    value: VitalsFormat.percent(controller.snapshot.diskFraction),
                    detailLabel: "Used",
                    detailValue: "\(VitalsFormat.bytes(controller.snapshot.diskUsedBytes)) / \(VitalsFormat.bytes(controller.snapshot.diskTotalBytes))",
                    history: controller.diskValues(),
                    tint: VitalsColor.disk
                )
                CompactMetricCard(
                    title: "Free space",
                    value: VitalsFormat.bytes(controller.snapshot.diskFreeBytes),
                    detailLabel: "Capacity",
                    detailValue: VitalsFormat.bytes(controller.snapshot.diskTotalBytes),
                    history: controller.diskValues().map { 1 - $0 },
                    tint: VitalsColor.npu
                )
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Capacity").font(.system(size: 12, weight: .semibold))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(VitalsColor.disk)
                                .frame(width: geo.size.width * controller.snapshot.diskFraction)
                        }
                    }
                    .frame(height: 10)
                    HStack {
                        Text("Used \(VitalsFormat.percent(controller.snapshot.diskFraction))")
                        Spacer()
                        Text("Free \(VitalsFormat.bytes(controller.snapshot.diskFreeBytes))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    Text("Disk fill history for \(controller.rangeDisplayLabel()). Growth is typically slow; short windows may look flat.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fill over time").font(.system(size: 12, weight: .semibold))
                    Sparkline(values: controller.diskValues(), tint: VitalsColor.disk)
                        .frame(height: 120)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct AIUsageDetailView: View {
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Local session metadata")
                            .font(.system(size: 11))
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
                    Divider()
                    HStack(alignment: .top, spacing: 18) {
                        usageSummary("Codex", controller.usage.codex, VitalsColor.codex)
                        Divider()
                        usageSummary("Claude", controller.usage.claude, VitalsColor.claude)
                    }
                    Text("Totals include input, output, and cached tokens reported by each provider. Vitals never opens credential files or sends usage data.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func usageSummary(_ title: String, _ summary: UsageSummary, _ tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(tint).frame(width: 8, height: 8)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let status = summary.displayStatus {
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text(VitalsFormat.compactTokens(summary.totalTokens))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                metric("Input", VitalsFormat.compactTokens(summary.inputTokens))
                metric("Output", VitalsFormat.compactTokens(summary.outputTokens))
                metric("Cached", VitalsFormat.compactTokens(summary.cachedTokens))
                metric("Sessions", "\(summary.sessions)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProcessesDetailView: View {
    @EnvironmentObject private var controller: MonitorController
    @State private var searchText = ""

    private var visibleProcesses: [ProcessMetric] {
        guard !searchText.isEmpty else { return controller.sortedProcesses }
        return controller.sortedProcesses.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            String($0.pid).contains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search name or PID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Picker("Sort", selection: $controller.processSort) {
                    ForEach(ProcessSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Text(searchText.isEmpty ? "Top \(controller.sortedProcesses.count) processes" : "\(visibleProcesses.count) matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PID").frame(width: 60, alignment: .trailing)
                        Text("CPU").frame(width: 70, alignment: .trailing)
                        Text("Memory").frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                    ForEach(visibleProcesses) { process in
                        HStack {
                            HStack(spacing: 8) {
                                processIcon(process)
                                Text(process.name)
                                    .lineLimit(1)
                                    .help(process.path ?? process.name)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(process.pid)")
                                .frame(width: 60, alignment: .trailing)
                                .monospacedDigit()
                            Text(String(format: "%.1f%%", process.cpuUsage))
                                .frame(width: 70, alignment: .trailing)
                                .monospacedDigit()
                            Text(VitalsFormat.bytes(process.memoryBytes))
                                .frame(width: 80, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 6)
                        Divider()
                    }

                    if visibleProcesses.isEmpty {
                        Text(controller.sortedProcesses.isEmpty ? "Waiting for process sample…" : "No processes match your search.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
