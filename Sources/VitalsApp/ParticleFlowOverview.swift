import SwiftUI
import VitalsCore

/// Glanceable overview: four current vitals, three history lanes, and exceptions.
/// Bars are data-bound to retained samples (left = older, right = now; height 0–100%).
struct ParticleFlowOverview: View {
    @EnvironmentObject private var controller: MonitorController
    @Environment(\.colorScheme) private var colorScheme

    private let barSlotCount = 48

    /// Single shared bar frame so every lane uses identical time buckets.
    private var bars: MonitorController.OverviewBarFrame {
        controller.overviewBarFrame(count: barSlotCount)
    }

    var body: some View {
        let frame = bars
        return VStack(spacing: 0) {
            metricStrip
            legendBar
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    historyLane(
                        title: "CPU",
                        value: VitalsFormat.percent(controller.snapshot.cpuUsage),
                        values: unitBars(frame.cpu),
                        tint: VitalsColor.cpu,
                        barDuration: frame.barDuration,
                        tooltipKind: .percent
                    )
                    Divider().opacity(colorScheme == .dark ? 0.25 : 0.55)
                    memoryLane(frame: frame)
                    Divider().opacity(colorScheme == .dark ? 0.25 : 0.55)
                    historyLane(
                        title: "Network",
                        value: VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond),
                        values: rateBars(frame.download),
                        tint: VitalsColor.network,
                        barDuration: frame.barDuration,
                        tooltipKind: .downloadRate,
                        rawValues: frame.download,
                        scaleCaption: "0–\(VitalsFormat.rate(networkChartCeiling))"
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(colorScheme == .dark ? 0.25 : 0.55)

                sidePanel
                    .frame(width: 200)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(fieldBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Metric strip

    private var metricStrip: some View {
        HStack(spacing: 1) {
            stripCell(
                title: "CPU",
                value: VitalsFormat.percent(controller.snapshot.cpuUsage),
                hint: "Load \(String(format: "%.2f", controller.snapshot.loadAverage))",
                fraction: controller.snapshot.cpuUsage,
                tint: VitalsColor.cpu
            )
            stripCell(
                title: "Memory",
                value: VitalsFormat.percent(controller.snapshot.memoryFraction),
                hint: memoryStripHint,
                fraction: controller.snapshot.memoryFraction,
                tint: VitalsColor.memory
            )
            stripCell(
                title: "Network",
                value: VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond),
                hint: "↑ \(VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond))",
                fraction: networkBarFraction,
                tint: VitalsColor.network
            )
            stripCell(
                title: "Battery",
                value: controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC",
                hint: batteryDetail,
                fraction: controller.snapshot.batteryLevel ?? 1,
                tint: VitalsColor.battery
            )
        }
        .background(stripDivider)
    }

    private func stripCell(
        title: String,
        value: String,
        hint: String,
        fraction: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.35), value: fraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(hint)")
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 12) {
            legendKey(color: VitalsColor.memoryWired, label: "Wired")
            legendKey(color: VitalsColor.memoryActive, label: "Active")
            legendKey(color: VitalsColor.memoryInactive, label: "Inactive")
            legendKey(color: VitalsColor.memoryCompressed, label: "Compressed")
            legendKey(color: VitalsColor.memorySwap, label: "Swap")
            Spacer(minLength: 0)
            Text("Memory composition")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(legendBackground)
        .overlay(alignment: .bottom) {
            Divider().opacity(colorScheme == .dark ? 0.2 : 0.5)
        }
    }

    private func legendKey(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History lanes

    private func historyLane(
        title: String,
        value: String,
        values: [Double],
        tint: Color,
        barDuration: TimeInterval,
        tooltipKind: HistoryBarTooltipKind,
        rawValues: [Double]? = nil,
        scaleCaption: String? = nil
    ) -> some View {
        HStack(spacing: 0) {
            laneLabel(title: title, value: value, tint: tint)
            HistoryBarChart(
                values: values,
                tint: tint,
                dimOlder: true,
                metricName: title,
                barDuration: barDuration,
                tooltipKind: tooltipKind,
                rawValues: rawValues
            )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(laneTint(tint).opacity(0.12))
                .overlay(alignment: .topTrailing) {
                    if let scaleCaption {
                        Text(scaleCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .accessibilityLabel("Chart scale \(scaleCaption)")
                    }
                }
                .accessibilityLabel("\(title) history bar chart, latest \(value)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func memoryLane(frame: MonitorController.OverviewBarFrame) -> some View {
        let mem = controller.snapshot.memory
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MEMORY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VitalsColor.memory)
                    .tracking(0.8)
                Text(VitalsFormat.percent(mem.usedFraction))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(VitalsColor.memory)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(VitalsFormat.bytes(mem.usedBytes)) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(VitalsFormat.bytes(mem.availableBytes)) free")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if mem.swapUsedBytes > 0 || mem.swapTotalBytes > 0 {
                    Text("Swap \(VitalsFormat.bytes(mem.swapUsedBytes))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VitalsColor.memorySwap)
                        .lineLimit(1)
                }
            }
            .frame(width: 88, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(
                LinearGradient(
                    colors: [
                        laneTint(VitalsColor.memory).opacity(0.55),
                        laneTint(VitalsColor.memory).opacity(0.05),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                // Current composition — hover each segment for exact % / size
                MemoryCompositionBar(memory: mem)
                    .frame(height: 18)
                    .padding(.bottom, 4) // room for tooltip below the strip

                // Same wall-clock buckets as CPU / network
                MemoryHistoryChart(
                    used: unitBars(frame.memory),
                    swap: unitBars(frame.swap),
                    barDuration: frame.barDuration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Compact numeric breakdown
                MemoryBreakdownLegend(memory: mem)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(laneTint(VitalsColor.memory).opacity(0.12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(memoryAccessibilityLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func laneLabel(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 80, alignment: .leading)
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .center)
        .background(
            LinearGradient(
                colors: [laneTint(tint).opacity(0.55), laneTint(tint).opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Side + footer

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sideGroup(title: "Status note") {
                Text(attentionMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sideGroup(title: "Activity") {
                sideRow("Upload", VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond))
                sideRow("Disk used", VitalsFormat.percent(controller.snapshot.diskFraction))
                sideRow("Top app", topProcessName)
                sideRow("Load (1m)", String(format: "%.2f", controller.snapshot.loadAverage))
            }

            sideGroup(title: "Machine") {
                sideRow("Cores", "\(controller.snapshot.processorCount)")
                sideRow("Thermal", controller.snapshot.thermalLevel.label)
                sideRow("Uptime", VitalsFormat.duration(controller.snapshot.uptime))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sideBackground)
    }

    private var memoryStripHint: String {
        let mem = controller.snapshot.memory
        let free = VitalsFormat.bytes(mem.availableBytes)
        if mem.swapUsedBytes > 0 {
            return "\(free) free · swap \(VitalsFormat.bytes(mem.swapUsedBytes))"
        }
        return "\(VitalsFormat.bytes(mem.usedBytes)) used · \(free) free"
    }

    private var memoryAccessibilityLabel: String {
        let mem = controller.snapshot.memory
        return "Memory \(VitalsFormat.percent(mem.usedFraction)). Wired \(VitalsFormat.bytes(mem.wiredBytes)), active \(VitalsFormat.bytes(mem.activeBytes)), inactive \(VitalsFormat.bytes(mem.inactiveBytes)), compressed \(VitalsFormat.bytes(mem.compressedBytes)), free \(VitalsFormat.bytes(mem.availableBytes)), swap \(VitalsFormat.bytes(mem.swapUsedBytes))."
    }

    private func sideGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)
            content()
        }
    }

    private var loadGrid: some View {
        HStack(spacing: 0) {
            loadCell("1m", controller.snapshot.loadAverage)
            loadCell("5m", controller.snapshot.loadAverage5)
            loadCell("15m", controller.snapshot.loadAverage15)
        }
        .padding(.vertical, 4)
    }

    private func loadCell(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.2f", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sideRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 6)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .font(.system(size: 12))
        .padding(.vertical, 3)
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Text("Status")
                    .foregroundStyle(.secondary)
                Text(statusLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Text(controller.rangeDisplayLabel())
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(footerBackground)
        .overlay(alignment: .top) {
            Divider().opacity(colorScheme == .dark ? 0.2 : 0.5)
        }
    }

    // MARK: - Data helpers

    /// Clamp unit metrics (CPU/memory/swap fractions) already bucketed by time.
    private func unitBars(_ source: [Double]) -> [Double] {
        source.map { min(max($0, 0), 1) }
    }

    /// Scale rates against a labeled, rounded ceiling with a 1 MB/s floor.
    /// This prevents tiny background traffic from looking like a saturated link.
    private func rateBars(_ source: [Double]) -> [Double] {
        source.map { min(max($0 / networkChartCeiling, 0), 1) }
    }

    private var networkChartCeiling: Double {
        let peak = max(bars.download.max() ?? 0, controller.snapshot.downloadBytesPerSecond)
        let tiers: [Double] = [1_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000]
        return tiers.first(where: { $0 >= peak }) ?? ceil(peak / 1_000_000_000) * 1_000_000_000
    }

    private var networkBarFraction: Double {
        min(max(controller.snapshot.downloadBytesPerSecond / networkChartCeiling, 0), 1)
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

    private var topProcessName: String {
        controller.sortedProcesses.first?.name ?? "—"
    }

    private var statusLabel: String {
        if let level = controller.snapshot.batteryLevel, level < 0.2 {
            return "Low battery"
        }
        if controller.snapshot.cpuUsage > 0.85 {
            return "CPU heavy"
        }
        if controller.snapshot.thermalLevel.isElevated {
            return controller.snapshot.thermalLevel.label
        }
        if controller.snapshot.downloadBytesPerSecond > 30 * 1_000_000 {
            return "Network busy"
        }
        if controller.snapshot.cpuUsage < 0.15 && controller.snapshot.downloadBytesPerSecond < 1_000_000 {
            return "Idle"
        }
        return "Healthy"
    }

    private var attentionMessage: String {
        if controller.snapshot.thermalLevel.isElevated {
            return "Thermals are elevated (\(controller.snapshot.thermalLevel.label))."
        }
        if let level = controller.snapshot.batteryLevel, level < 0.2 {
            return "Battery is below 20%."
        }
        if controller.snapshot.cpuUsage > 0.85 {
            return "CPU usage is sustained above 85%."
        }
        if controller.snapshot.memory.swapUsedBytes > 0 {
            return "Swap is in use. High memory occupancy alone is not treated as pressure."
        }
        return "No immediate issues detected."
    }

    private var statusColor: Color {
        switch statusLabel {
        case "Healthy", "Idle", "Network busy":
            return VitalsColor.battery
        default:
            return VitalsColor.memory
        }
    }

    private var accessibilitySummary: String {
        "Overview. CPU \(VitalsFormat.percent(controller.snapshot.cpuUsage)), memory \(VitalsFormat.percent(controller.snapshot.memoryFraction)), download \(VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond)), battery \(controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC"). Status \(statusLabel)."
    }

    // MARK: - Surfaces

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.03, green: 0.04, blue: 0.06)
            : Color(red: 0.97, green: 0.975, blue: 0.985)
    }

    private var cardSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.05, green: 0.055, blue: 0.08)
            : Color.white
    }

    private var stripDivider: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    private var fieldBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    private var legendBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.03)
    }

    private var sideBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.02)
    }

    private var footerBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.04, green: 0.045, blue: 0.07)
            : Color(red: 0.96, green: 0.965, blue: 0.975)
    }

    private func laneTint(_ tint: Color) -> Color {
        tint.opacity(colorScheme == .dark ? 0.35 : 0.2)
    }
}

// MARK: - History bar chart

enum HistoryBarTooltipKind {
    case percent
    case downloadRate
    case memory
}

/// Floating tooltip while the pointer moves across a chart / composition bar.
private struct ChartHoverTooltip: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let anchor: CGPoint
    let container: CGSize
    /// Prefer placing the bubble below the anchor (needed for short rows like the composition strip).
    var preferBelow: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        // Short containers (composition strip): always sit below so text isn't clipped.
        var y: CGFloat
        if preferBelow || container.height < 40 {
            y = container.height + bubbleH / 2 + 8
        } else {
            // Prefer above the cursor; fall back inside the plot if needed.
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
    /// Map pointer X to a bar index using equal slot width (gaps count as part of the nearest bar).
    static func barIndex(x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0 else { return nil }
        let clamped = min(max(x, 0), width - 0.001)
        let index = Int(clamped / width * CGFloat(count))
        return min(max(index, 0), count - 1)
    }
}

/// Vertical bars for a 0–1 series. Left = older, right = newer. Height fills bottom→top.
struct HistoryBarChart: View {
    let values: [Double]
    let tint: Color
    var dimOlder: Bool = true
    var metricName: String = ""
    var barDuration: TimeInterval = 0
    var tooltipKind: HistoryBarTooltipKind = .percent
    /// Un-normalized values for tooltips (e.g. raw download rates). Defaults to `values`.
    var rawValues: [Double]? = nil

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = max(1, geo.size.width > 400 ? 2.5 : 1.5)
            let barWidth = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let height = geo.size.height
            let raw = rawValues ?? values
            let slotWidth = geo.size.width / CGFloat(count)

            ZStack(alignment: .bottomLeading) {
                // Highlight column under pointer (full slot width).
                if let index = hoverIndex {
                    let x = (CGFloat(index) + 0.5) * slotWidth
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: max(slotWidth, barWidth + gap), height: height)
                        .position(x: x, y: height / 2)
                        .allowsHitTesting(false)
                }

                // Bars
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, displayRaw in
                        let value = min(max(displayRaw, 0), 1)
                        let age = values.count <= 1 ? 1.0 : Double(index) / Double(values.count - 1)
                        let opacity = dimOlder ? (0.35 + age * 0.55) : 0.85
                        let barHeight: CGFloat = value < 0.000_5 ? 0 : max(2, height * CGFloat(value))
                        let highlighted = hoverIndex == index

                        RoundedRectangle(cornerRadius: min(barWidth / 2, 3), style: .continuous)
                            .fill(tint.opacity(highlighted ? min(1, opacity + 0.18) : opacity))
                            .frame(width: barWidth, height: barHeight)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .bottom)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.25), value: values)

                // Full-plot hit target — entire lane area tracks the pointer.
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
        let position = "Bar \(index + 1)/\(count)"
        let span = barDuration > 0 ? " · \(VitalsFormat.duration(barDuration))/bar" : ""
        switch tooltipKind {
        case .percent, .memory:
            if raw < 0.000_5 && display < 0.000_5 {
                return "\(metricName) \(position)\(span)\nNo samples · 0%"
            }
            return "\(metricName) \(position)\(span)\n\(VitalsFormat.percent(raw))"
        case .downloadRate:
            let scaleShare = display > 0.000_5 ? "\n\(VitalsFormat.percent(display)) of chart scale" : ""
            return "\(metricName) \(position)\(span)\n\(VitalsFormat.rate(raw))\(scaleShare)"
        }
    }
}

// MARK: - Memory history (used + swap)

struct MemoryHistoryChart: View {
    let used: [Double]
    let swap: [Double]
    var barDuration: TimeInterval = 0

    @State private var hoverIndex: Int?
    @State private var hoverPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            let count = max(max(used.count, swap.count), 1)
            let gap: CGFloat = max(1, geo.size.width > 400 ? 2.5 : 1.5)
            let barWidth = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let height = geo.size.height
            let swapBand = height * 0.28
            let slotWidth = geo.size.width / CGFloat(count)

            ZStack(alignment: .bottomLeading) {
                if let index = hoverIndex {
                    let x = (CGFloat(index) + 0.5) * slotWidth
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(VitalsColor.memory.opacity(0.14))
                        .frame(width: max(slotWidth, barWidth + gap), height: height)
                        .position(x: x, y: height / 2)
                        .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<count, id: \.self) { index in
                        let u = index < used.count ? min(max(used[index], 0), 1) : 0
                        let s = index < swap.count ? min(max(swap[index], 0), 1) : 0
                        let age = count <= 1 ? 1.0 : Double(index) / Double(count - 1)
                        let usedHeight: CGFloat = u < 0.000_5 ? 0 : max(2, height * CGFloat(u))

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: min(barWidth / 2, 3), style: .continuous)
                                .fill(VitalsColor.memory.opacity(0.35 + age * 0.55))
                                .frame(width: barWidth, height: usedHeight)
                            if s > 0.002 {
                                RoundedRectangle(cornerRadius: min(barWidth / 2, 2), style: .continuous)
                                    .fill(VitalsColor.memorySwap.opacity(0.55 + age * 0.4))
                                    .frame(width: barWidth, height: max(2, swapBand * CGFloat(min(s * 4, 1))))
                            }
                        }
                        .frame(width: barWidth, height: height, alignment: .bottom)
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .bottom)
                .allowsHitTesting(false)

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
        let position = "Bar \(index + 1)/\(count)"
        let span = barDuration > 0 ? " · \(VitalsFormat.duration(barDuration))/bar" : ""
        if u < 0.000_5 && s < 0.000_5 {
            return "Memory \(position)\(span)\nNo samples · 0%"
        }
        var lines = ["Memory \(position)\(span)", "Used \(VitalsFormat.percent(u))"]
        if s > 0.000_5 {
            lines.append("Swap \(VitalsFormat.percent(s)) of RAM")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Memory composition

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
        // Physical RAM only (swap is separate and shown in the side panel / legend).
        return [
            Segment(id: "w", name: "Wired", color: VitalsColor.memoryWired, bytes: memory.wiredBytes, fraction: Double(memory.wiredBytes) / t),
            Segment(id: "a", name: "Active", color: VitalsColor.memoryActive, bytes: memory.activeBytes, fraction: Double(memory.activeBytes) / t),
            Segment(id: "i", name: "Inactive", color: VitalsColor.memoryInactive, bytes: memory.inactiveBytes, fraction: Double(memory.inactiveBytes) / t),
            Segment(id: "c", name: "Compressed", color: VitalsColor.memoryCompressed, bytes: memory.compressedBytes, fraction: Double(memory.compressedBytes) / t),
            Segment(id: "f", name: "Free", color: VitalsColor.memoryFree, bytes: memory.availableBytes, fraction: Double(memory.availableBytes) / t),
        ].filter { $0.bytes > 0 || $0.id == "f" }
    }

    var body: some View {
        GeometryReader { geo in
            let parts = segments
            let total = max(parts.reduce(0) { $0 + $1.fraction }, 0.0001)
            // Cumulative widths for hit-testing any X across the full bar.
            let widths: [CGFloat] = parts.map { max(2, geo.size.width * CGFloat($0.fraction / total)) }
            let ends: [CGFloat] = widths.reduce(into: [CGFloat]()) { acc, w in
                acc.append((acc.last ?? 0) + w)
            }
            // Extra vertical space below the strip so tooltips aren't clipped by the parent.
            let stripHeight = geo.size.height
            let plotSize = CGSize(width: geo.size.width, height: stripHeight)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        let width = widths[index]
                        let highlighted = hoverIndex == index
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(part.color)
                            .opacity(highlighted ? 1 : 0.9)
                            .frame(width: width, height: stripHeight)
                            .overlay {
                                if highlighted {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                                }
                            }
                    }
                }
                .frame(width: geo.size.width, height: stripHeight, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .allowsHitTesting(false)

                // Full-width hit target so every segment is easy to hit.
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

                // Tooltip drawn *outside* the clipped strip so each segment tip is fully visible.
                if let index = hoverIndex, index < parts.count {
                    let part = parts[index]
                    ChartHoverTooltip(
                        text: "\(part.name)\n\(VitalsFormat.percent(part.fraction)) of RAM\n\(VitalsFormat.bytes(part.bytes))",
                        anchor: hoverPoint,
                        container: plotSize,
                        preferBelow: true
                    )
                }
            }
            .frame(width: geo.size.width, height: stripHeight, alignment: .topLeading)
            // Allow tooltip to paint below the strip without being clipped here.
            .padding(.bottom, 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                parts.map { "\($0.name) \(VitalsFormat.percent($0.fraction)), \(VitalsFormat.bytes($0.bytes))" }
                    .joined(separator: ", ")
            )
        }
    }

    private static func segmentIndex(x: CGFloat, ends: [CGFloat]) -> Int? {
        guard !ends.isEmpty else { return nil }
        let clamped = min(max(x, 0), (ends.last ?? 0) - 0.001)
        for (i, end) in ends.enumerated() where clamped < end {
            return i
        }
        return ends.count - 1
    }
}

struct MemoryBreakdownLegend: View {
    let memory: MemoryBreakdown

    var body: some View {
        HStack(spacing: 10) {
            legendItem("W", VitalsColor.memoryWired, memory.wiredBytes)
            legendItem("A", VitalsColor.memoryActive, memory.activeBytes)
            legendItem("I", VitalsColor.memoryInactive, memory.inactiveBytes)
            legendItem("C", VitalsColor.memoryCompressed, memory.compressedBytes)
            legendItem("F", VitalsColor.memoryFree, memory.availableBytes)
            if memory.swapUsedBytes > 0 || memory.swapTotalBytes > 0 {
                legendItem("S", VitalsColor.memorySwap, memory.swapUsedBytes)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
    }

    private func legendItem(_ short: String, _ color: Color, _ bytes: UInt64) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(short)
                .foregroundStyle(.secondary)
            Text(VitalsFormat.compactBytes(bytes))
                .foregroundStyle(.primary.opacity(0.85))
                .monospacedDigit()
        }
    }
}

private extension VitalsFormat {
    /// Shorter byte labels for tight legends (e.g. 1.2G).
    static func compactBytes(_ value: UInt64) -> String {
        let v = Double(value)
        if v >= 1_073_741_824 {
            return String(format: "%.1fG", v / 1_073_741_824)
        }
        if v >= 1_048_576 {
            return String(format: "%.0fM", v / 1_048_576)
        }
        if v >= 1_024 {
            return String(format: "%.0fK", v / 1_024)
        }
        return "\(value)B"
    }
}
