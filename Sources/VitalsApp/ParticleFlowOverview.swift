import SwiftUI
import VitalsCore
import VKit

/// Glanceable overview: a "now" strip, three full-width history lanes with a
/// shared time axis, and an attention rail (status + top processes + machine).
///
/// Design rules for this surface:
/// - The strip owns current values; lanes own history. No number twice.
/// - Charts use absolute scales (0–100% or a labeled rate ceiling); flat
///   series must read as flat.
/// - Side rail is for *exceptions and action*, not restating the strip.
/// - Every horizontal band earns its height.
struct ParticleFlowOverview: View {
    @EnvironmentObject private var controller: MonitorController
    @Environment(\.colorScheme) private var colorScheme
    var onOpenProcesses: (() -> Void)? = nil

    private let barSlotCount = 56
    private let sideWidth: CGFloat = 228

    private var bars: MonitorController.OverviewBarFrame {
        controller.overviewBarFrame(count: barSlotCount)
    }

    var body: some View {
        let frame = bars
        return VStack(spacing: 0) {
            metricStrip
            HStack(alignment: .top, spacing: 0) {
                GeometryReader { geo in
                    let cpuShare: CGFloat = 0.30
                    let memShare: CGFloat = 0.40
                    let netShare: CGFloat = 0.30
                    let axisH: CGFloat = 20
                    let dividerH: CGFloat = 1
                    let usable = max(0, geo.size.height - dividerH * 2 - axisH)
                    VStack(spacing: 0) {
                        cpuLane(frame: frame)
                            .frame(height: usable * cpuShare)
                        laneDivider
                        memoryLane(frame: frame)
                            .frame(height: usable * memShare)
                        laneDivider
                        networkLane(frame: frame)
                            .frame(height: usable * netShare)
                        timeAxisRow(frame: frame)
                            .frame(height: axisH)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                sidePanel
                    .frame(width: sideWidth)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: VRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VRadius.field, style: .continuous)
                .stroke(fieldBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Metric strip (current values)

    private var showsDiskCell: Bool {
        controller.snapshot.batteryPowerState == .noBattery
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            stripCell(
                title: "CPU",
                value: VitalsFormat.percent(controller.snapshot.cpuUsage),
                hint: "Load \(String(format: "%.2f", controller.snapshot.loadAverage))",
                fraction: controller.snapshot.cpuUsage,
                history: unitValues(controller.cpuValues()),
                tint: VitalsColor.cpu,
                textTint: VitalsColor.cpuText
            )
            stripDividerLine
            stripCell(
                title: "Memory",
                value: VitalsFormat.percent(controller.snapshot.memoryFraction),
                hint: memoryStripHint,
                fraction: controller.snapshot.memoryFraction,
                history: unitValues(controller.memoryValues()),
                tint: VitalsColor.memory,
                textTint: VitalsColor.memoryText
            )
            stripDividerLine
            stripCell(
                title: "Network",
                value: "↓ \(VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond))",
                hint: "↑ \(VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond))",
                fraction: nil, // unbounded metric — no capacity capsule
                history: controller.downloadValues(),
                tint: VitalsColor.network,
                textTint: VitalsColor.networkText,
                scale: .rate(ceiling: networkChartCeiling)
            )
            stripDividerLine
            stripCell(
                title: "Disk",
                value: VitalsFormat.percent(controller.snapshot.diskFraction),
                hint: "\(VitalsFormat.bytes(controller.snapshot.diskFreeBytes)) free",
                fraction: controller.snapshot.diskFraction,
                history: unitValues(controller.diskValues()),
                tint: VitalsColor.disk,
                textTint: VitalsColor.diskText
            )
            if !showsDiskCell {
                stripDividerLine
                stripCell(
                    title: "Battery",
                    value: controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC",
                    hint: batteryDetail,
                    fraction: controller.snapshot.batteryLevel ?? 1,
                    history: unitValues(controller.batteryValues()),
                    tint: VitalsColor.battery,
                    textTint: VitalsColor.batteryText
                )
            }
        }
        .background(cardSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(hairline).frame(height: 1)
        }
    }

    private var stripDividerLine: some View {
        Rectangle()
            .fill(hairline)
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private func stripCell(
        title: String,
        value: String,
        hint: String,
        fraction: Double?,
        history: [Double],
        tint: Color,
        textTint: Color,
        scale: SparklineScale = .unit
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(title).kicker()
                }
                Text(value)
                    .font(VText.metricL)
                    .foregroundStyle(textTint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(hint)
                    .font(VText.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Sparkline(values: history, tint: tint, scale: scale)
                    .frame(width: 72, height: fraction == nil ? 31 : 22)
                if let fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(tint.opacity(0.9))
                                .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                                .animation(.easeOut(duration: 0.3), value: fraction)
                        }
                    }
                    .frame(width: 72, height: 3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(hint)")
    }

    // MARK: - History lanes

    private var laneDivider: some View {
        Rectangle().fill(hairline).frame(height: 1)
    }

    /// Lane header drawn inside the plot: kicker + lane-unique secondary facts.
    private func laneHeader(_ title: String, tint: Color, secondary: [(String, Color)]) -> some View {
        HStack(spacing: 8) {
            Text(title).kicker(tint)
            ForEach(Array(secondary.enumerated()), id: \.offset) { _, item in
                Text(item.0)
                    .font(VText.caption)
                    .foregroundStyle(item.1)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.leading, 12)
        .padding(.top, 7)
    }

    private func cpuLane(frame: MonitorController.OverviewBarFrame) -> some View {
        ZStack(alignment: .topLeading) {
            HistoryBarChart(
                values: unitBars(frame.cpu),
                tint: VitalsColor.cpu,
                metricName: "CPU",
                barDuration: frame.barDuration,
                windowEnd: frame.windowEnd,
                tooltipKind: .percent,
                showBaseline: true
            )
            .padding(.horizontal, 12)
            .padding(.top, 26)
            .padding(.bottom, 8)
            laneHeader(
                "CPU",
                tint: VitalsColor.cpuText,
                secondary: [(cpuLoadDetail, .secondary)]
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            scaleCaption("0–100%")
        }
        .background(laneSurface(VitalsColor.cpu))
    }

    private func memoryLane(frame: MonitorController.OverviewBarFrame) -> some View {
        let mem = controller.snapshot.memory
        // Strip owns used/free bytes; the lane's unique fact is swap.
        var secondary: [(String, Color)] = []
        if mem.swapUsedBytes > 0 {
            secondary.append(("Swap \(VitalsFormat.bytes(mem.swapUsedBytes))", VitalsColor.memorySwapText))
        }
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                MemoryHistoryChart(
                    used: unitBars(frame.memory),
                    swap: unitBars(frame.swap),
                    barDuration: frame.barDuration,
                    windowEnd: frame.windowEnd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                MemoryCompositionBar(memory: mem)
                    .frame(height: 10)
                MemoryBreakdownLegend(memory: mem)
            }
            .padding(.horizontal, 12)
            .padding(.top, 26)
            .padding(.bottom, 8)
            laneHeader("Memory", tint: VitalsColor.memoryText, secondary: secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            scaleCaption("0–100%")
        }
        .background(laneSurface(VitalsColor.memory))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(memoryAccessibilityLabel)
    }

    private func networkLane(frame: MonitorController.OverviewBarFrame) -> some View {
        var secondary: [(String, Color)] = [
            ("↑ \(VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond))", VitalsColor.uploadText)
        ]
        if let interface = controller.snapshot.primaryInterfaceName {
            secondary.append((interface, .secondary))
        }
        return ZStack(alignment: .topLeading) {
            DualRateBarChart(
                download: rateBars(frame.download),
                upload: rateBars(frame.upload),
                downloadRaw: frame.download,
                uploadRaw: frame.upload,
                barDuration: frame.barDuration,
                windowEnd: frame.windowEnd,
                downloadTint: VitalsColor.network,
                uploadTint: VitalsColor.upload
            )
            .padding(.horizontal, 12)
            .padding(.top, 26)
            .padding(.bottom, 8)
            laneHeader("Network", tint: VitalsColor.networkText, secondary: secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            scaleCaption("0–\(VitalsFormat.rate(networkChartCeiling))")
        }
        .background(laneSurface(VitalsColor.network))
    }

    private func scaleCaption(_ text: String) -> some View {
        Text(text)
            .font(VText.micro)
            .foregroundStyle(.secondary)
            .padding(.trailing, 10)
            .padding(.top, 8)
    }

    /// Shared wall-clock axis for all three lanes (they use the same grid).
    private func timeAxisRow(frame: MonitorController.OverviewBarFrame) -> some View {
        let start = frame.windowEnd.addingTimeInterval(-frame.windowDuration)
        let tickCount = 4
        let ticks = (0...tickCount).map { index in
            start.addingTimeInterval(frame.windowDuration * Double(index) / Double(tickCount))
        }
        return HStack(spacing: 0) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, date in
                if index > 0 { Spacer() }
                Text(index == tickCount ? "now" : VitalsFormat.axisTime(date, span: frame.windowDuration))
                    .font(VText.micro)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if frame.windowDuration + 0.5 < frame.range.duration {
                Text("filling")
                    .font(VText.micro)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                    .padding(.leading, 8)
                    .help("Charts zoom to retained samples until the full \(frame.range.label) window is available")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(hairline).frame(height: 1)
        }
    }

    private func laneSurface(_ tint: Color) -> some View {
        ZStack(alignment: .leading) {
            // Soft tinted field — low enough that empty charts don't look like voids.
            (colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.35))
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(colorScheme == .dark ? 0.10 : 0.04), location: 0),
                    .init(color: tint.opacity(0.0), location: 0.22),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            // Accent rail on the label edge
            Rectangle()
                .fill(tint.opacity(colorScheme == .dark ? 0.55 : 0.45))
                .frame(width: 2)
        }
    }

    // MARK: - Side rail (attention + action)

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard

            sideGroup(title: topProcessesTitle, action: onOpenProcesses) {
                if topProcesses.isEmpty {
                    Text("Waiting for process sample…")
                        .font(VText.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(topProcesses.enumerated()), id: \.element.id) { index, process in
                        processRow(process)
                        if index < topProcesses.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            sideGroup(title: "Machine") {
                VStack(alignment: .leading, spacing: 5) {
                    machineRow("Chip", controller.snapshot.processorName)
                    machineRow("Cores", "\(controller.snapshot.processorCount)")
                    machineRow(
                        "Thermal",
                        controller.snapshot.thermalLevel.label,
                        valueColor: controller.snapshot.thermalLevel.isElevated ? VitalsColor.thermalText : nil
                    )
                    machineRow("Uptime", VitalsFormat.duration(controller.snapshot.uptime))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sideBackground)
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.label)
                    .font(VText.bodyStrong)
                    .foregroundStyle(status.color)
                Text(status.message)
                    .font(VText.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            status.color.opacity(status.isAttention ? (colorScheme == .dark ? 0.12 : 0.08) : 0.0),
            in: RoundedRectangle(cornerRadius: VRadius.chip + 2, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: VRadius.chip + 2, style: .continuous)
                .stroke(status.color.opacity(status.isAttention ? 0.22 : 0.14), lineWidth: 1)
        }
    }

    private func processRow(_ process: ProcessMetric) -> some View {
        HStack(spacing: 7) {
            processIcon(process)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(VText.captionStrong)
                    .lineLimit(1)
                    .help(process.path ?? process.name)
                Text(processDetail(process))
                    .font(VText.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func processDetail(_ process: ProcessMetric) -> String {
        if prioritizeMemoryProcesses {
            return "\(VitalsFormat.bytes(process.memoryBytes)) · \(String(format: "%.0f%%", process.cpuUsage)) CPU"
        }
        return "\(String(format: "%.0f%%", process.cpuUsage)) CPU · \(VitalsFormat.bytes(process.memoryBytes))"
    }

    @ViewBuilder private func processIcon(_ process: ProcessMetric) -> some View {
        if let icon = ProcessIconLookup.icon(for: process) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
        }
    }

    private func machineRow(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(VText.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(VText.captionStrong)
                .foregroundStyle(valueColor ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .help(value)
            Spacer(minLength: 0)
        }
    }

    private func sideGroup<Content: View>(
        title: String,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(title).kicker()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Open Processes")
            } else {
                Text(title).kicker()
            }
            content()
        }
    }

    // MARK: - Data helpers

    /// The strip owns the 1-minute load; the lane adds the longer horizons.
    private var cpuLoadDetail: String {
        let s = controller.snapshot
        return String(format: "Load 5m %.2f · 15m %.2f", s.loadAverage5, s.loadAverage15)
    }

    /// Prefer memory-sorted processes when memory/swap is the story; otherwise CPU.
    private var topProcesses: [ProcessMetric] {
        let list: [ProcessMetric]
        if prioritizeMemoryProcesses {
            list = controller.snapshot.topProcesses.sorted { $0.memoryBytes > $1.memoryBytes }
        } else {
            list = controller.snapshot.topProcesses.sorted { $0.cpuUsage > $1.cpuUsage }
        }
        return Array(list.prefix(5))
    }

    private var topProcessesTitle: String {
        prioritizeMemoryProcesses ? "Top by memory" : "Top by CPU"
    }

    private var prioritizeMemoryProcesses: Bool {
        controller.snapshot.memory.swapUsedBytes > 0
            || controller.snapshot.memoryFraction >= 0.85
    }

    private func unitBars(_ source: [Double]) -> [Double] {
        source.map { min(max($0, 0), 1) }
    }

    private func unitValues(_ source: [Double]) -> [Double] {
        source.map { min(max($0, 0), 1) }
    }

    private func rateBars(_ source: [Double]) -> [Double] {
        source.map { min(max($0 / networkChartCeiling, 0), 1) }
    }

    private var networkChartCeiling: Double {
        RateScale.ceiling(for: max(
            bars.download.max() ?? 0,
            bars.upload.max() ?? 0,
            controller.snapshot.downloadBytesPerSecond,
            controller.snapshot.uploadBytesPerSecond
        ))
    }

    /// Total RAM appears nowhere else; used/free live in the lane legend.
    private var memoryStripHint: String {
        "\(VitalsFormat.bytes(controller.snapshot.memory.usedBytes)) of \(VitalsFormat.bytes(controller.snapshot.memory.totalBytes))"
    }

    private var memoryAccessibilityLabel: String {
        let mem = controller.snapshot.memory
        return "Memory \(VitalsFormat.percent(mem.usedFraction)). Wired \(VitalsFormat.bytes(mem.wiredBytes)), active \(VitalsFormat.bytes(mem.activeBytes)), inactive \(VitalsFormat.bytes(mem.inactiveBytes)), compressed \(VitalsFormat.bytes(mem.compressedBytes)), free \(VitalsFormat.bytes(mem.availableBytes)), swap \(VitalsFormat.bytes(mem.swapUsedBytes))."
    }

    private var batteryDetail: String {
        switch controller.snapshot.batteryPowerState {
        case .noBattery: return "Desktop"
        case .charging: return "Charging"
        case .chargedOnAC: return "Full"
        case .onBattery:
            return controller.snapshot.batteryTimeRemaining.map(VitalsFormat.duration) ?? "On battery"
        }
    }

    // MARK: - Status

    private struct Status {
        var label: String
        var message: String
        var color: Color
        /// Attention states get a tinted card; informational ones stay quiet.
        var isAttention: Bool
    }

    private var status: Status {
        let snapshot = controller.snapshot
        if snapshot.thermalLevel.isElevated {
            return Status(
                label: snapshot.thermalLevel.label,
                message: "Thermals elevated — expect throttling under sustained load.",
                color: VitalsColor.thermalText,
                isAttention: true
            )
        }
        if let level = snapshot.batteryLevel, level < 0.2 {
            return Status(
                label: "Low battery",
                message: "Battery below 20%. Plug in when you can.",
                color: VitalsColor.memoryText,
                isAttention: true
            )
        }
        if snapshot.cpuUsage > 0.85 {
            return Status(
                label: "CPU heavy",
                message: "CPU above 85%. Check top processes.",
                color: VitalsColor.memoryText,
                isAttention: true
            )
        }
        if snapshot.memoryFraction >= 0.9 && snapshot.memory.swapUsedBytes > 512 * 1_024 * 1_024 {
            return Status(
                label: "Memory tight",
                message: "Memory nearly full and swapping. Review top apps if you feel lag.",
                color: VitalsColor.memorySwapText,
                isAttention: true
            )
        }
        if snapshot.memory.swapUsedBytes > 0 {
            return Status(
                label: "Healthy",
                message: "Some swap in use — normal on macOS. Occupancy is not pressure.",
                color: VitalsColor.batteryText,
                isAttention: false
            )
        }
        if snapshot.cpuUsage < 0.15 && snapshot.downloadBytesPerSecond < 1_000_000 {
            return Status(
                label: "Idle",
                message: "No immediate issues.",
                color: VitalsColor.batteryText,
                isAttention: false
            )
        }
        return Status(
            label: "Healthy",
            message: "No immediate issues.",
            color: VitalsColor.batteryText,
            isAttention: false
        )
    }

    private var accessibilitySummary: String {
        "Overview. CPU \(VitalsFormat.percent(controller.snapshot.cpuUsage)), memory \(VitalsFormat.percent(controller.snapshot.memoryFraction)), download \(VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond)), battery \(controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC"). Status \(status.label)."
    }

    // MARK: - Surfaces

    private var fieldBackground: Color { Palette.background }
    private var cardSurface: Color {
        colorScheme == .dark ? Palette.surface.opacity(0.55) : Color.white.opacity(0.72)
    }
    private var fieldBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }
    private var hairline: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08)
    }
    private var sideBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.025)
    }
}

// MARK: - Chart shared bits

enum HistoryBarTooltipKind {
    case percent
    case downloadRate
    case memory
}

/// Floating tooltip while the pointer moves across a chart / composition bar.
private struct ChartHoverTooltip: View {
    let text: String
    let anchor: CGPoint
    let container: CGSize
    var preferBelow: Bool = false

    var body: some View {
        Text(text)
            .font(VText.captionStrong)
            .foregroundStyle(Color.white)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: VRadius.chip + 2, style: .continuous)
                    .fill(Palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: VRadius.chip + 2, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
            .fixedSize()
            .position(clampedPosition)
            .allowsHitTesting(false)
            .zIndex(1000)
    }

    private var clampedPosition: CGPoint {
        let bubbleW: CGFloat = 170
        let bubbleH: CGFloat = 58
        let margin: CGFloat = 6
        var x = anchor.x
        var y: CGFloat
        if preferBelow || container.height < 40 {
            y = min(container.height - bubbleH / 2 - margin, anchor.y + bubbleH / 2 + 10)
            if y < bubbleH / 2 + margin { y = bubbleH / 2 + margin }
        } else {
            y = anchor.y - bubbleH / 2 - 12
            if y < bubbleH / 2 + margin {
                y = anchor.y + bubbleH / 2 + 12
            }
            y = min(max(y, bubbleH / 2 + margin), max(bubbleH / 2 + margin, container.height - bubbleH / 2 - margin))
        }
        x = min(max(x, bubbleW / 2 + margin), max(bubbleW / 2 + margin, container.width - bubbleW / 2 - margin))
        return CGPoint(x: x, y: y)
    }
}

private enum ChartHoverMath {
    static func barIndex(x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0 else { return nil }
        let clamped = min(max(x, 0), width - 0.001)
        let index = Int(clamped / width * CGFloat(count))
        return min(max(index, 0), count - 1)
    }

    /// Wall-clock interval for a bucket, e.g. "14:32–14:33".
    static func bucketInterval(index: Int, count: Int, barDuration: TimeInterval, windowEnd: Date) -> String {
        guard barDuration > 0 else { return "" }
        let start = windowEnd.addingTimeInterval(-barDuration * Double(count - index))
        let end = start.addingTimeInterval(barDuration)
        return "\(VitalsFormat.shortTime(start))–\(VitalsFormat.shortTime(end))"
    }
}

/// Vertical bars for a 0–1 series. Left = older, right = newer.
/// Uniform opacity — the data varies, the ink does not.
struct HistoryBarChart: View {
    let values: [Double]
    let tint: Color
    var metricName: String = ""
    var barDuration: TimeInterval = 0
    var windowEnd: Date = Date()
    var tooltipKind: HistoryBarTooltipKind = .percent
    var rawValues: [Double]? = nil
    var showBaseline: Bool = false

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = max(1, geo.size.width > 400 ? 2.0 : 1.2)
            let barWidth = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let height = geo.size.height
            let raw = rawValues ?? values
            let slotWidth = geo.size.width / CGFloat(count)

            ZStack(alignment: .bottomLeading) {
                if showBaseline {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height - 0.5))
                        path.addLine(to: CGPoint(x: geo.size.width, y: height - 0.5))
                    }
                    .stroke(tint.opacity(0.18), lineWidth: 1)
                    .allowsHitTesting(false)
                }

                if let index = hoverIndex {
                    let x = (CGFloat(index) + 0.5) * slotWidth
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: max(slotWidth, barWidth + gap), height: height)
                        .position(x: x, y: height / 2)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, displayRaw in
                        let value = min(max(displayRaw, 0), 1)
                        let isLive = index == values.count - 1
                        let opacity = isLive ? 1.0 : 0.78
                        let barHeight: CGFloat = value < 0.000_5 ? 0 : max(2, height * CGFloat(value))
                        let highlighted = hoverIndex == index

                        RoundedRectangle(cornerRadius: min(barWidth / 2, 2.5), style: .continuous)
                            .fill(tint.opacity(highlighted ? 1.0 : opacity))
                            .frame(width: barWidth, height: barHeight)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .bottom)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.25), value: values)

                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .frame(width: geo.size.width, height: height)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPoint = location
                            hoverIndex = ChartHoverMath.barIndex(
                                x: location.x,
                                width: geo.size.width,
                                count: count
                            )
                        case .ended:
                            hoverIndex = nil
                        }
                    }

                if let index = hoverIndex {
                    let display = index < values.count ? min(max(values[index], 0), 1) : 0
                    let tipRaw = index < raw.count ? raw[index] : display
                    ChartHoverTooltip(
                        text: tooltipText(index: index, count: count, raw: tipRaw, display: display),
                        anchor: hoverPoint,
                        container: geo.size
                    )
                }
            }
            .frame(width: geo.size.width, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        guard let last = values.last else { return "\(metricName) history unavailable" }
        return "\(metricName) latest \(tooltipKind == .downloadRate ? VitalsFormat.rate(rawValues?.last ?? last) : VitalsFormat.percent(last))"
    }

    private func tooltipText(index: Int, count: Int, raw: Double, display: Double) -> String {
        let interval = ChartHoverMath.bucketInterval(
            index: index, count: count, barDuration: barDuration, windowEnd: windowEnd
        )
        let heading = interval.isEmpty ? metricName : "\(metricName) \(interval)"
        switch tooltipKind {
        case .percent, .memory:
            if raw < 0.000_5 && display < 0.000_5 {
                return "\(heading)\nNo samples · 0%"
            }
            return "\(heading)\n\(VitalsFormat.percent(raw))"
        case .downloadRate:
            return "\(heading)\n\(VitalsFormat.rate(raw))"
        }
    }
}

// MARK: - Dual download / upload bars

struct DualRateBarChart: View {
    let download: [Double]
    let upload: [Double]
    var downloadRaw: [Double] = []
    var uploadRaw: [Double] = []
    var barDuration: TimeInterval = 0
    var windowEnd: Date = Date()
    var downloadTint: Color = VitalsColor.network
    var uploadTint: Color = VitalsColor.upload

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let count = max(max(download.count, upload.count), 1)
            let gap: CGFloat = max(1, geo.size.width > 400 ? 2.0 : 1.2)
            let barWidth = max(3, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let height = geo.size.height
            let slotWidth = geo.size.width / CGFloat(count)

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height - 0.5))
                    path.addLine(to: CGPoint(x: geo.size.width, y: height - 0.5))
                }
                .stroke(downloadTint.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)

                if let index = hoverIndex {
                    let x = (CGFloat(index) + 0.5) * slotWidth
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(downloadTint.opacity(0.12))
                        .frame(width: max(slotWidth, barWidth + gap), height: height)
                        .position(x: x, y: height / 2)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<count, id: \.self) { index in
                        let d = index < download.count ? min(max(download[index], 0), 1) : 0
                        let u = index < upload.count ? min(max(upload[index], 0), 1) : 0
                        let isLive = index == count - 1
                        let opacity = isLive ? 1.0 : 0.78
                        let scale = max(d + u, 1)
                        let dHeight = d < 0.000_5 ? 0 : max(2, height * CGFloat(d / scale))
                        let uHeight = u < 0.000_5 ? 0 : max(2, height * CGFloat(u / scale))

                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(uploadTint.opacity(opacity))
                                .frame(width: barWidth, height: uHeight)
                            Rectangle()
                                .fill(downloadTint.opacity(opacity))
                                .frame(width: barWidth, height: dHeight)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: min(barWidth / 2, 2.5), style: .continuous))
                        .frame(width: barWidth, height: height, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .bottom)
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPoint = location
                            hoverIndex = ChartHoverMath.barIndex(x: location.x, width: geo.size.width, count: count)
                        case .ended:
                            hoverIndex = nil
                        }
                    }

                if let index = hoverIndex {
                    let dRaw = index < downloadRaw.count ? downloadRaw[index] : (index < download.count ? download[index] : 0)
                    let uRaw = index < uploadRaw.count ? uploadRaw[index] : (index < upload.count ? upload[index] : 0)
                    let interval = ChartHoverMath.bucketInterval(
                        index: index, count: count, barDuration: barDuration, windowEnd: windowEnd
                    )
                    ChartHoverTooltip(
                        text: "Network \(interval)\n↓ \(VitalsFormat.rate(dRaw))\n↑ \(VitalsFormat.rate(uRaw))",
                        anchor: hoverPoint,
                        container: geo.size
                    )
                }
            }
        }
    }
}

// MARK: - Memory history (used + swap bars)

/// Memory uses the same wall-clock bar language as CPU and network. Each slot
/// pairs used RAM with swap on the same 0–100% physical-RAM scale.
struct MemoryHistoryChart: View {
    let used: [Double]
    let swap: [Double]
    var barDuration: TimeInterval = 0
    var windowEnd: Date = Date()

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let count = max(max(used.count, swap.count), 1)
            let height = geo.size.height
            let slotWidth = geo.size.width / CGFloat(count)
            let gap: CGFloat = max(1, geo.size.width > 400 ? 2.0 : 1.2)
            let barWidth = max(3, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height - 0.5))
                    path.addLine(to: CGPoint(x: geo.size.width, y: height - 0.5))
                }
                .stroke(VitalsColor.memory.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<count, id: \.self) { index in
                        let u = index < used.count ? min(max(used[index], 0), 1) : 0
                        let s = index < swap.count ? min(max(swap[index], 0), 1) : 0
                        let isLive = index == count - 1
                        let opacity = isLive ? 1.0 : 0.78
                        let scale = max(u + s, 1)
                        let usedHeight = u < 0.000_5 ? 0 : max(2, height * CGFloat(u / scale))
                        let swapHeight = s < 0.000_5 ? 0 : max(1.5, height * CGFloat(s / scale))

                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(VitalsColor.memorySwap.opacity(opacity))
                                .frame(width: barWidth, height: swapHeight)
                            Rectangle()
                                .fill(VitalsColor.memory.opacity(opacity))
                                .frame(width: barWidth, height: usedHeight)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: min(barWidth / 2, 2.5), style: .continuous))
                        .frame(width: barWidth, height: height, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .bottom)
                .allowsHitTesting(false)

                if let index = hoverIndex {
                    let x = (CGFloat(index) + 0.5) * slotWidth
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(VitalsColor.memory.opacity(0.14))
                        .frame(width: slotWidth, height: height)
                        .position(x: x, y: height / 2)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .frame(width: geo.size.width, height: height)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPoint = location
                            hoverIndex = ChartHoverMath.barIndex(
                                x: location.x,
                                width: geo.size.width,
                                count: count
                            )
                        case .ended:
                            hoverIndex = nil
                        }
                    }

                if let index = hoverIndex {
                    ChartHoverTooltip(
                        text: memoryTooltip(index: index, count: count),
                        anchor: hoverPoint,
                        container: geo.size
                    )
                }
            }
            .frame(width: geo.size.width, height: height)
        }
    }

    private func memoryTooltip(index: Int, count: Int) -> String {
        let u = index < used.count ? min(max(used[index], 0), 1) : 0
        let s = index < swap.count ? min(max(swap[index], 0), 1) : 0
        let interval = ChartHoverMath.bucketInterval(
            index: index, count: count, barDuration: barDuration, windowEnd: windowEnd
        )
        if u < 0.000_5 && s < 0.000_5 {
            return "Memory \(interval)\nNo samples · 0%"
        }
        var lines = ["Memory \(interval)", "Used \(VitalsFormat.percent(u))"]
        if s > 0.000_5 {
            lines.append("Swap \(VitalsFormat.percent(s)) of RAM")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Memory composition

/// Used-memory composition on a neutral track: the unfilled remainder *is*
/// free memory, so free is not painted as another colored consumer.
struct MemoryCompositionBar: View {
    let memory: MemoryBreakdown

    private struct Segment: Identifiable {
        let id: String
        let name: String
        let color: Color
        let bytes: UInt64
        let fraction: Double
    }

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    private var segments: [Segment] {
        guard memory.totalBytes > 0 else { return [] }
        let t = Double(memory.totalBytes)
        return [
            Segment(id: "w", name: "Wired", color: VitalsColor.memoryWired, bytes: memory.wiredBytes, fraction: Double(memory.wiredBytes) / t),
            Segment(id: "a", name: "Active", color: VitalsColor.memoryActive, bytes: memory.activeBytes, fraction: Double(memory.activeBytes) / t),
            Segment(id: "i", name: "Inactive", color: VitalsColor.memoryInactive, bytes: memory.inactiveBytes, fraction: Double(memory.inactiveBytes) / t),
            Segment(id: "c", name: "Compressed", color: VitalsColor.memoryCompressed, bytes: memory.compressedBytes, fraction: Double(memory.compressedBytes) / t),
        ].filter { $0.bytes > 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let parts = segments
            let widths: [CGFloat] = parts.map { max(2, geo.size.width * CGFloat($0.fraction)) }
            let ends: [CGFloat] = widths.reduce(into: [CGFloat]()) { acc, w in
                acc.append((acc.last ?? 0) + w)
            }
            let stripHeight = geo.size.height

            ZStack(alignment: .topLeading) {
                // Neutral track = total RAM; the uncovered tail is free memory.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: geo.size.width, height: stripHeight)

                HStack(spacing: 1) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        let width = widths[index]
                        let highlighted = hoverIndex == index
                        Rectangle()
                            .fill(part.color)
                            .opacity(highlighted ? 1 : 0.92)
                            .frame(width: width, height: stripHeight)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .frame(width: geo.size.width, height: stripHeight)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverPoint = location
                            hoverIndex = Self.segmentIndex(x: location.x, ends: ends)
                        case .ended:
                            hoverIndex = nil
                        }
                    }

                if let index = hoverIndex {
                    ChartHoverTooltip(
                        text: tooltipText(index: index, parts: parts),
                        anchor: hoverPoint,
                        container: CGSize(width: geo.size.width, height: stripHeight),
                        preferBelow: true
                    )
                }
            }
            .frame(width: geo.size.width, height: stripHeight, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(for: parts))
        }
    }

    private func tooltipText(index: Int, parts: [Segment]) -> String {
        if index < parts.count {
            let part = parts[index]
            return "\(part.name)\n\(VitalsFormat.percent(part.fraction)) of RAM\n\(VitalsFormat.bytes(part.bytes))"
        }
        return "Free\n\(VitalsFormat.percent(memory.freeFraction)) of RAM\n\(VitalsFormat.bytes(memory.availableBytes))"
    }

    private func accessibilityText(for parts: [Segment]) -> String {
        var pieces: [String] = parts.map { part in
            "\(part.name) \(VitalsFormat.percent(part.fraction)), \(VitalsFormat.bytes(part.bytes))"
        }
        let freePercent = VitalsFormat.percent(memory.freeFraction)
        let freeBytes = VitalsFormat.bytes(memory.availableBytes)
        pieces.append("Free \(freePercent), \(freeBytes)")
        return pieces.joined(separator: ", ")
    }

    /// Hovers past the last colored segment resolve to the free-track region.
    private static func segmentIndex(x: CGFloat, ends: [CGFloat]) -> Int? {
        guard !ends.isEmpty else { return nil }
        let clamped = max(x, 0)
        for (i, end) in ends.enumerated() where clamped < end {
            return i
        }
        return ends.count // free region
    }
}

struct MemoryBreakdownLegend: View {
    let memory: MemoryBreakdown

    var body: some View {
        HStack(spacing: 10) {
            legendItem("Wired", VitalsColor.memoryWired, memory.wiredBytes)
            legendItem("Active", VitalsColor.memoryActive, memory.activeBytes)
            legendItem("Inactive", VitalsColor.memoryInactive, memory.inactiveBytes)
            legendItem("Compressed", VitalsColor.memoryCompressed, memory.compressedBytes)
            legendItem("Free", VitalsColor.memoryFree, memory.availableBytes)
            Spacer(minLength: 0)
        }
        .font(VText.caption)
    }

    private func legendItem(_ name: String, _ color: Color, _ bytes: UInt64) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(name)
                .foregroundStyle(.secondary)
            Text(VitalsFormat.bytes(bytes))
                .foregroundStyle(.primary.opacity(0.85))
                .monospacedDigit()
        }
        .lineLimit(1)
    }
}
