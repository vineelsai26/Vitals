import AppKit
import SwiftUI
import VitalsCore

enum MenuPanel: String {
    case system
    case aiUsage
}

struct MenuBarView: View {
    @EnvironmentObject private var controller: MonitorController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var panel: MenuPanel

    init(initialPanel: MenuPanel = .system) {
        _panel = State(initialValue: initialPanel)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        Text(panel == .system ? "System" : "AI Usage Today")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Circle()
                            .fill(controller.isRunning ? .green : .secondary)
                            .frame(width: 6, height: 6)
                    }
                }
                .buttonStyle(.plain)
                .help("Open Vitals")

                if let error = controller.errorMessage {
                    Text(error)
                        .font(.system(size: 9))
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
                toolbarButton(panel == .system ? "brain.head.profile" : "chart.xyaxis.line", selected: false) {
                    panel = panel == .system ? .aiUsage : .system
                }
                toolbarButton(controller.isRunning ? "pause.circle" : "play.circle", selected: false) {
                    controller.toggleRunning()
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.plain)
                .help("Settings")
                toolbarButton("power", selected: false) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var systemRows: some View {
        VStack(spacing: 10) {
            metricRow("CPU", value: VitalsFormat.percent(controller.snapshot.cpuUsage), history: controller.cpuValues(), detail: String(format: "%.2f", controller.snapshot.loadAverage), tint: VitalsColor.cpu)
            metricRow("Memory", value: VitalsFormat.percent(controller.snapshot.memoryFraction), history: controller.memoryValues(), detail: VitalsFormat.bytes(controller.snapshot.memoryUsedBytes), tint: VitalsColor.memory)
            metricRow("Disk", value: VitalsFormat.percent(controller.snapshot.diskFraction), history: controller.diskValues(), detail: VitalsFormat.bytes(controller.snapshot.diskFreeBytes) + " free", tint: VitalsColor.disk)
            metricRow("Down", value: VitalsFormat.rate(controller.snapshot.downloadBytesPerSecond), history: controller.downloadValues(), detail: controller.snapshot.primaryInterfaceName ?? "—", tint: VitalsColor.network)
            metricRow("Up", value: VitalsFormat.rate(controller.snapshot.uploadBytesPerSecond), history: controller.uploadValues(), detail: controller.snapshot.primaryInterfaceName ?? "—", tint: VitalsColor.upload)
            metricRow("Battery", value: controller.snapshot.batteryLevel.map(VitalsFormat.percent) ?? "AC", history: controller.batteryValues(), detail: batteryDetail, tint: VitalsColor.battery)
        }
    }

    private var usageRows: some View {
        VStack(spacing: 10) {
            usageRow("Codex", systemImage: "chevron.left.forwardslash.chevron.right", summary: controller.usage.codex)
            if let status = controller.usage.codex.displayStatus {
                Text(status).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            usageRow("Claude", systemImage: "sparkles", summary: controller.usage.claude)
            if let status = controller.usage.claude.displayStatus {
                Text(status).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Sessions").foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.usage.totalSessions)")
                Text("Total Tokens").foregroundStyle(.secondary).padding(.leading, 12)
                Text(VitalsFormat.compactTokens(controller.usage.totalTokens))
            }
            .font(.system(size: 9.5))
            .monospacedDigit()
        }
    }

    private func metricRow(
        _ title: String,
        value: String,
        history: [Double],
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10))
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)
            Sparkline(values: history, tint: tint)
                .frame(width: 54, height: 15)
            Spacer(minLength: 2)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func usageRow(_ title: String, systemImage: String, summary: UsageSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            Text(title).font(.system(size: 10))
            Spacer()
            Text("\(summary.sessions) sessions")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text(VitalsFormat.compactTokens(summary.totalTokens))
                .font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func toolbarButton(_ systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(selected ? VitalsColor.cpu : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        .help(systemImage == "power" ? "Quit Vitals" : "")
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
