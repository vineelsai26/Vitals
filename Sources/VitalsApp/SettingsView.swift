import SwiftUI
import VitalsCore

struct SettingsView: View {
    var body: some View {
        SettingsForm()
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(width: 520)
            .frame(minHeight: 600)
    }
}

/// Native settings-window content.
struct SettingsForm: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: MonitorController

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Menu bar", selection: $settings.menuBarLabel) {
                    ForEach(MenuBarLabel.allCases) { label in
                        Text(label.label).tag(label)
                    }
                }

                Picker("Default history range", selection: $settings.historyRange) {
                    ForEach(HistoryTimeRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .onChange(of: settings.historyRange) { _, newValue in
                    controller.setHistoryRange(newValue)
                }
            }

            Section("Monitoring") {
                Picker("Refresh every", selection: $settings.refreshCadence) {
                    ForEach(RefreshCadence.allCases) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                Toggle("Read Codex session usage", isOn: $settings.codexUsageEnabled)
                Toggle("Read Claude session usage", isOn: $settings.claudeUsageEnabled)
                Text("Vitals reads token counts and timestamps locally. It never reads credential files or sends usage data anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SystemSnapshot.memoryDefinitionNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Alerts") {
                Toggle("Enable threshold alerts", isOn: $settings.alertsEnabled)
                Toggle("Notify on elevated thermal state", isOn: $settings.alertOnThermal)
                    .disabled(!settings.alertsEnabled)
                thresholdRow("Memory threshold", value: $settings.alertMemoryThreshold, range: 0.7...0.98)
                thresholdRow("Battery threshold", value: $settings.alertBatteryThreshold, range: 0.05...0.30)
                Text("Alerts use macOS notifications and respect a 15-minute cooldown per kind.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("App behavior") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Start in the menu bar", isOn: $settings.startInMenuBar)
                Toggle("Keep running after closing the window", isOn: $settings.closeToMenuBar)
                Toggle("Show Vitals in the Dock", isOn: $settings.showInDock)
                Text("Menu bar mode controls how Vitals starts. Keeping it running preserves monitoring after its window closes; Dock visibility only changes how you switch back to it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                Text("Local-first system monitor for macOS. Open source in the vstack monorepo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func thresholdRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 0.01)
                    .frame(width: 180)
                Text(VitalsFormat.percent(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .disabled(!settings.alertsEnabled)
    }
}
