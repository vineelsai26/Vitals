import AppKit
import SwiftUI
import VitalsCore
import VKit

enum MenuPanel: String {
    case system
    case aiUsage
}

struct MenuBarView: View {
    @EnvironmentObject private var controller: MonitorController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var panel: MenuPanel
    @State private var headerHovered = false

    init(initialPanel: MenuPanel = .system) {
        _panel = State(initialValue: initialPanel)
    }

    private var rateCeiling: Double {
        RateScale.ceiling(for: max(
            controller.downloadValues().max() ?? 0,
            controller.uploadValues().max() ?? 0,
            controller.snapshot.downloadBytesPerSecond,
            controller.snapshot.uploadBytesPerSecond
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 5) {
                        Text(panel == .system ? "System" : "AI Usage Today")
                            .font(VText.bodyStrong)
                        if panel == .system {
                            Text("· \(controller.historyRange.label)")
                                .font(VText.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(headerHovered ? .secondary : .tertiary)
                        Spacer()
                        if !controller.isRunning {
                            Text("Paused")
                                .font(VText.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.14), in: Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { headerHovered = $0 }
                .help("Open Vitals")

                if let error = controller.errorMessage {
                    Text(error)
                        .font(VText.caption)
                        .foregroundStyle(.orange)
                }

                if panel == .system {
                    systemRows
                } else {
                    usageRows
                }
            }
            .padding(14)

            Divider()

            HStack(spacing: 0) {
                toolbarButton(
                    panel == .system ? "brain.head.profile" : "gauge.with.dots.needle.50percent",
                    help: panel == .system ? "Show AI usage" : "Show system metrics"
                ) {
                    panel = panel == .system ? .aiUsage : .system
                }
                toolbarButton(
                    controller.isRunning ? "pause.circle" : "play.circle",
                    help: controller.isRunning ? "Pause monitoring" : "Resume monitoring"
                ) {
                    controller.toggleRunning()
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                Divider().frame(height: 16)
                toolbarButton("power", help: "Quit Vitals") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 300)
        .background(Palette.background)
    }

    private var systemRows: some View {
        VStack(spacing: 10) {
            metricRow(
                "CPU",
                value: VitalsFormat.percent(controller.snapshot.cpuUsage),
                detail: "Load \(String(format: "%.2f", controller.snapshot.loadAverage))",
                tint: VitalsColor.cpu,
                textTint: VitalsColor.cpuText
            ) {
                Sparkline(values: controller.cpuValues(), tint: VitalsColor.cpu, scale: .unit)
            }
            metricRow(
                "Memory",
                value: VitalsFormat.percent(controller.snapshot.memoryFraction),
                detail: "\(VitalsFormat.bytes(controller.snapshot.memoryUsedBytes)) used",
                tint: VitalsColor.memory,
                textTint: VitalsColor.memoryText
            ) {
                Sparkline(values: controller.memoryValues(), tint: VitalsColor.memory, scale: .unit)
            }
            metricRow(
                "Disk",
                value: VitalsFormat.percent(controller.snapshot.diskFraction),
                detail: "\(VitalsFormat.bytes(controller.snapshot.diskFreeBytes)) free",
                tint: VitalsColor.disk,
                textTint: VitalsColor.diskText
            ) {
                // A near-constant level has no shape worth drawing — show capacity.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(VitalsColor.disk.opacity(0.9))
                            .frame(width: max(2, geo.size.width * controller.snapshot.diskFraction))
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            metricRow(
                "Network",
                value: "↓ \(VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond))",
                detail: networkDetail,
                tint: VitalsColor.network,
                textTint: VitalsColor.networkText
            ) {
                Sparkline(
                    values: controller.downloadValues(),
                    tint: VitalsColor.network,
                    scale: .rate(ceiling: rateCeiling)
                )
            }
            metricRow(
                "Battery",
                value: controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC",
                detail: batteryDetail,
                tint: VitalsColor.battery,
                textTint: VitalsColor.batteryText
            ) {
                Sparkline(values: controller.batteryValues(), tint: VitalsColor.battery, scale: .unit)
            }
        }
    }

    private var networkDetail: String {
        "↑ \(VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond))"
    }

    private var usageRows: some View {
        VStack(spacing: 10) {
            usageRow("Codex", systemImage: "chevron.left.forwardslash.chevron.right", summary: controller.usage.codex)
            usageRow("Claude", systemImage: "sparkles", summary: controller.usage.claude)
            Divider()
            HStack {
                Text("Today").foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.usage.totalSessions) sessions · \(VitalsFormat.compactTokens(controller.usage.totalTokens)) tokens")
                    .monospacedDigit()
            }
            .font(VText.caption)
        }
    }

    private func metricRow<Chart: View>(
        _ title: String,
        value: String,
        detail: String,
        tint: Color,
        textTint: Color,
        @ViewBuilder chart: () -> Chart
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(VText.caption)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(VText.captionStrong)
                .foregroundStyle(textTint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 62, alignment: .leading)
            chart()
                .frame(width: 56, height: 15)
            Spacer(minLength: 2)
            Text(detail)
                .font(VText.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value), \(detail)")
    }

    private func usageRow(_ title: String, systemImage: String, summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                Text(title).font(VText.caption)
                Spacer()
                Text("\(summary.sessions) sessions")
                    .font(VText.caption).foregroundStyle(.secondary)
                Text(VitalsFormat.compactTokens(summary.totalTokens))
                    .font(VText.captionStrong).monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            HStack {
                if let status = summary.displayStatus {
                    Text(status).font(VText.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let last = summary.lastActivity {
                    Text("Last \(VitalsFormat.shortTime(last))")
                        .font(VText.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.leading, 26)
        }
    }

    private func toolbarButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var batteryDetail: String {
        switch controller.snapshot.batteryPowerState {
        case .noBattery: return "Desktop"
        case .charging: return "Charging"
        case .chargedOnAC: return "Full"
        case .onBattery:
            return controller.snapshot.batteryTimeRemaining.map(VitalsFormat.duration) ?? "Estimating"
        }
    }
}

struct MenuBarLabelText: View {
    @EnvironmentObject private var controller: MonitorController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            switch settings.menuBarLabel {
            case .icon:
                EmptyView()
            case .cpu:
                Text(VitalsFormat.percent(controller.snapshot.cpuUsage))
            case .memory:
                Text(VitalsFormat.percent(controller.snapshot.memoryFraction))
            case .cpuAndMemory:
                Text("\(VitalsFormat.percent(controller.snapshot.cpuUsage)) · \(VitalsFormat.percent(controller.snapshot.memoryFraction))")
            case .network:
                Text("↓\(VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond))")
            case .aiTokens:
                Text(VitalsFormat.compactTokens(controller.usage.totalTokens))
            }
        }
        .monospacedDigit()
    }
}
