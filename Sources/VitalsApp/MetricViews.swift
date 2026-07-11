import AppKit
import SwiftUI
import VitalsCore

enum VitalsColor {
    static let cpu = Color(red: 0.12, green: 0.43, blue: 0.98)
    static let gpu = Color(red: 0.47, green: 0.23, blue: 0.96)
    static let npu = Color(red: 0.12, green: 0.58, blue: 0.27)
    static let memory = Color(red: 1.00, green: 0.36, blue: 0.04)
    static let memoryWired = Color(red: 0.75, green: 0.22, blue: 0.12)
    static let memoryActive = Color(red: 1.00, green: 0.45, blue: 0.12)
    static let memoryInactive = Color(red: 0.95, green: 0.62, blue: 0.28)
    static let memoryCompressed = Color(red: 0.72, green: 0.38, blue: 0.85)
    static let memoryFree = Color(red: 0.35, green: 0.42, blue: 0.48)
    static let memorySwap = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let battery = Color(red: 0.10, green: 0.55, blue: 0.25)
    static let network = Color(red: 0.08, green: 0.53, blue: 0.94)
    static let disk = Color(red: 0.15, green: 0.55, blue: 0.75)
    static let upload = Color(red: 0.55, green: 0.30, blue: 0.92)
    static let thermal = Color(red: 0.90, green: 0.35, blue: 0.15)
    static let codex = Color(red: 0.18, green: 0.48, blue: 0.96)
    static let claude = Color(red: 0.50, green: 0.28, blue: 0.92)
}

struct DashboardCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            }
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.075, blue: 0.105)
            : Color.white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.095)
    }
}

struct CompactMetricCard: View {
    let title: String
    let value: String
    let detailLabel: String
    let detailValue: String
    let history: [Double]
    let tint: Color
    var helpText: String? = nil

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Sparkline(values: history, tint: tint)
                    .frame(height: 30)
                    .accessibilityLabel(accessibilitySummary)
                HStack {
                    Text(detailLabel)
                    Spacer(minLength: 4)
                    Text(detailValue).monospacedDigit()
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(minWidth: 125, minHeight: 116)
        .help(helpText ?? "\(title): \(value). \(detailLabel) \(detailValue)")
    }

    private var accessibilitySummary: String {
        guard let last = history.last else { return "\(title) recent activity unavailable" }
        let avg = history.reduce(0, +) / Double(max(history.count, 1))
        return "\(title) average \(String(format: "%.0f", avg * 100)) percent, latest \(String(format: "%.0f", last * 100)) percent over \(history.count) samples"
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color
    var normalizeToUnit: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let source = values.isEmpty ? [0.5, 0.5] : values
        if normalizeToUnit {
            let range = max((source.max() ?? 1) - (source.min() ?? 0), 0.12)
            let floor = (source.min() ?? 0) - range * 0.18
            return source.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) / CGFloat(max(source.count - 1, 1)) * size.width,
                    y: size.height - CGFloat((value - floor) / (range * 1.36)) * size.height
                )
            }
        }
        let maxValue = max(source.max() ?? 1, 1)
        return source.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / CGFloat(max(source.count - 1, 1)) * size.width,
                y: size.height - CGFloat(value / maxValue) * size.height
            )
        }
    }
}

struct MultiLineChart: View {
    let series: [(values: [Double], color: Color, unitScale: ChartScale)]

    enum ChartScale {
        case unit
        case rate
    }

    var body: some View {
        GeometryReader { geometry in
            let sharedRatePeak = max(
                series.filter { $0.unitScale == .rate }.flatMap(\.values).max() ?? 0,
                1_000_000
            )
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider().opacity(0.30)
                        Spacer()
                    }
                }
                ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                    chartPath(
                        values: item.values,
                        scale: item.unitScale,
                        ratePeak: sharedRatePeak,
                        size: geometry.size
                    )
                        .stroke(item.color, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func chartPath(values: [Double], scale: ChartScale, ratePeak: Double, size: CGSize) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let normalized: [Double]
        switch scale {
        case .unit:
            normalized = values.map { min(max($0, 0), 1) }
        case .rate:
            normalized = values.map { min(max($0 / ratePeak, 0), 1) }
        }
        for (index, value) in normalized.enumerated() {
            let point = CGPoint(
                x: CGFloat(index) / CGFloat(max(normalized.count - 1, 1)) * size.width,
                y: (1 - CGFloat(value)) * size.height
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

struct ActivityPanel: View {
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("System Activity").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(controller.rangeDisplayLabel())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help("Shows available history for the selected range")
                }
                HStack(spacing: 12) {
                    legend("CPU", VitalsColor.cpu)
                    legend("Memory", VitalsColor.memory)
                    legend("Down*", VitalsColor.network)
                    legend("Up*", VitalsColor.upload)
                }
                Text("* Network series scaled to their own peak in this window")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 7) {
                    VStack {
                        Text("100%")
                        Spacer()
                        Text("50%")
                        Spacer()
                        Text("0%")
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 27)
                    MultiLineChart(series: [
                        (controller.cpuValues(), VitalsColor.cpu, .unit),
                        (controller.memoryValues(), VitalsColor.memory, .unit),
                        (controller.downloadValues(), VitalsColor.network, .rate),
                        (controller.uploadValues(), VitalsColor.upload, .rate),
                    ])
                    .accessibilityLabel(activityAccessibility)
                }
                .frame(maxHeight: .infinity)
                .frame(minHeight: 108)
                HStack {
                    ForEach(Array(controller.timeAxisLabels().enumerated()), id: \.offset) { index, date in
                        if index > 0 { Spacer() }
                        Text(VitalsFormat.axisTime(date, span: controller.historyRange.duration))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 8.5)).foregroundStyle(.secondary)
        }
    }

    private var activityAccessibility: String {
        let cpu = controller.cpuValues()
        let mem = controller.memoryValues()
        let cpuAvg = cpu.isEmpty ? 0 : cpu.reduce(0, +) / Double(cpu.count)
        let memAvg = mem.isEmpty ? 0 : mem.reduce(0, +) / Double(mem.count)
        return "System activity \(controller.rangeDisplayLabel()). CPU average \(VitalsFormat.percent(cpuAvg)), memory average \(VitalsFormat.percent(memAvg))."
    }
}

struct AIUsagePanel: View {
    @EnvironmentObject private var controller: MonitorController

    private var combinedTotal: UInt64 {
        controller.usage.totalTokens
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AI Usage Today").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Today")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                usageRow("Codex", systemImage: "chevron.left.forwardslash.chevron.right", summary: controller.usage.codex, tint: VitalsColor.codex)
                Divider()
                usageRow("Claude", systemImage: "sparkles", summary: controller.usage.claude, tint: VitalsColor.claude)
                Spacer(minLength: 2)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sessions").foregroundStyle(.secondary)
                        Text("\(controller.usage.totalSessions)").monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Total Tokens").foregroundStyle(.secondary)
                        Text(VitalsFormat.compactTokens(combinedTotal)).monospacedDigit()
                    }
                }
                .font(.system(size: 9.5))
            }
        }
    }

    private func usageRow(_ title: String, systemImage: String, summary: UsageSummary, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.system(size: 10.5, weight: .medium))
                        Spacer()
                        Text(VitalsFormat.compactTokens(summary.totalTokens))
                            .font(.system(size: 9.5)).monospacedDigit()
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(tint).frame(width: geometry.size.width * share(for: summary))
                        }
                    }
                    .frame(height: 4)
                }
            }
            if let status = summary.displayStatus {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func share(for summary: UsageSummary) -> Double {
        guard combinedTotal > 0 else { return 0 }
        return Double(summary.totalTokens) / Double(combinedTotal)
    }
}

struct ProcessPanel: View {
    let processes: [ProcessMetric]
    var limit: Int = 5

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Top Processes").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("CPU")
                    Text("Memory").frame(width: 52, alignment: .trailing)
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)

                ForEach(processes.prefix(limit)) { process in
                    HStack(spacing: 6) {
                        processIcon(process)
                        Text(process.name)
                            .font(.system(size: 9.5))
                            .lineLimit(1)
                            .help(process.path ?? process.name)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuUsage))
                            .font(.system(size: 9)).monospacedDigit()
                        Text(VitalsFormat.bytes(process.memoryBytes))
                            .font(.system(size: 9)).monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    if process.id != processes.prefix(limit).last?.id { Divider() }
                }

                if processes.isEmpty {
                    Text("Process activity will appear after the next refresh.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                }
            }
        }
    }

    @ViewBuilder private func processIcon(_ process: ProcessMetric) -> some View {
        if let image = applicationIcon(for: process) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 17, height: 17)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
        }
    }

    private func applicationIcon(for process: ProcessMetric) -> NSImage? {
        if let path = process.path {
            let url = URL(fileURLWithPath: path)
            if path.contains(".app") {
                var appURL = url
                while appURL.pathExtension != "app", appURL.path != "/" {
                    appURL.deleteLastPathComponent()
                }
                if appURL.pathExtension == "app" {
                    return NSWorkspace.shared.icon(forFile: appURL.path)
                }
            }
            if let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
                return NSWorkspace.shared.icon(forFile: app.path)
            }
        }
        let normalized = process.name.lowercased()
        return NSWorkspace.shared.runningApplications.first { application in
            guard let appName = application.localizedName?.lowercased() else { return false }
            return appName == normalized || appName.contains(normalized) || normalized.contains(appName)
        }?.icon
    }
}

struct StatusBanner: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
            Text(message)
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isError ? Color.orange : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
