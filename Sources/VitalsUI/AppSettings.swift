import AppKit
import ServiceManagement
import SwiftUI
import VitalsCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    mutating func cycle() {
        switch self {
        case .system: self = .light
        case .light: self = .dark
        case .dark: self = .system
        }
    }

    var toggleSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var toggleHelp: String {
        switch self {
        case .system: return "Theme: System (click for Light)"
        case .light: return "Theme: Light (click for Dark)"
        case .dark: return "Theme: Dark (click for System)"
        }
    }
}

enum RefreshCadence: Double, CaseIterable, Identifiable {
    case quick = 1
    case balanced = 2
    case relaxed = 5

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .quick: return "1 second"
        case .balanced: return "2 seconds"
        case .relaxed: return "5 seconds"
        }
    }
}

enum MenuBarLabel: String, CaseIterable, Identifiable {
    case icon
    case cpu
    case memory
    case cpuAndMemory
    case network
    case aiTokens

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon: return "Icon only"
        case .cpu: return "CPU percentage"
        case .memory: return "Memory percentage"
        case .cpuAndMemory: return "CPU · Memory"
        case .network: return "Network throughput"
        case .aiTokens: return "AI tokens today"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var refreshCadence: RefreshCadence {
        didSet { defaults.set(refreshCadence.rawValue, forKey: Keys.refreshCadence) }
    }
    @Published var menuBarLabel: MenuBarLabel {
        didSet { defaults.set(menuBarLabel.rawValue, forKey: Keys.menuBarLabel) }
    }
    @Published var historyRange: HistoryTimeRange {
        didSet { defaults.set(historyRange.rawValue, forKey: Keys.historyRange) }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }
    @Published var startInMenuBar: Bool {
        didSet { defaults.set(startInMenuBar, forKey: Keys.startInMenuBar) }
    }
    @Published var closeToMenuBar: Bool {
        didSet { defaults.set(closeToMenuBar, forKey: Keys.closeToMenuBar) }
    }
    @Published var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Keys.showInDock)
            applyActivationPolicy()
        }
    }
    @Published var codexUsageEnabled: Bool {
        didSet { defaults.set(codexUsageEnabled, forKey: Keys.codexUsageEnabled) }
    }
    @Published var claudeUsageEnabled: Bool {
        didSet { defaults.set(claudeUsageEnabled, forKey: Keys.claudeUsageEnabled) }
    }
    @Published var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }
    @Published var alertMemoryThreshold: Double {
        didSet { defaults.set(alertMemoryThreshold, forKey: Keys.alertMemoryThreshold) }
    }
    @Published var alertBatteryThreshold: Double {
        didSet { defaults.set(alertBatteryThreshold, forKey: Keys.alertBatteryThreshold) }
    }
    @Published var alertOnThermal: Bool {
        didSet { defaults.set(alertOnThermal, forKey: Keys.alertOnThermal) }
    }

    private enum Keys {
        static let appearance = "appearance"
        static let refreshCadence = "refreshCadence"
        static let menuBarLabel = "menuBarLabel"
        static let historyRange = "historyRange"
        static let startInMenuBar = "startInMenuBar"
        static let closeToMenuBar = "closeToMenuBar"
        static let showInDock = "showInDock"
        static let codexUsageEnabled = "codexUsageEnabled"
        static let claudeUsageEnabled = "claudeUsageEnabled"
        static let alertsEnabled = "alertsEnabled"
        static let alertMemoryThreshold = "alertMemoryThreshold"
        static let alertBatteryThreshold = "alertBatteryThreshold"
        static let alertOnThermal = "alertOnThermal"
    }

    private init() {
        defaults.register(defaults: [
            Keys.appearance: AppAppearance.system.rawValue,
            Keys.refreshCadence: RefreshCadence.balanced.rawValue,
            Keys.menuBarLabel: MenuBarLabel.cpuAndMemory.rawValue,
            Keys.historyRange: HistoryTimeRange.oneHour.rawValue,
            Keys.startInMenuBar: false,
            Keys.closeToMenuBar: true,
            Keys.showInDock: true,
            Keys.codexUsageEnabled: true,
            Keys.claudeUsageEnabled: true,
            Keys.alertsEnabled: false,
            Keys.alertMemoryThreshold: 0.90,
            Keys.alertBatteryThreshold: 0.10,
            Keys.alertOnThermal: true,
        ])
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        refreshCadence = RefreshCadence(rawValue: defaults.double(forKey: Keys.refreshCadence)) ?? .balanced
        let storedLabel = defaults.string(forKey: Keys.menuBarLabel) ?? ""
        menuBarLabel = MenuBarLabel(rawValue: storedLabel) ?? .cpuAndMemory
        historyRange = HistoryTimeRange(rawValue: defaults.string(forKey: Keys.historyRange) ?? "") ?? .oneHour
        startInMenuBar = defaults.bool(forKey: Keys.startInMenuBar)
        closeToMenuBar = defaults.bool(forKey: Keys.closeToMenuBar)
        showInDock = defaults.bool(forKey: Keys.showInDock)
        codexUsageEnabled = defaults.bool(forKey: Keys.codexUsageEnabled)
        claudeUsageEnabled = defaults.bool(forKey: Keys.claudeUsageEnabled)
        alertsEnabled = defaults.bool(forKey: Keys.alertsEnabled)
        alertMemoryThreshold = defaults.object(forKey: Keys.alertMemoryThreshold) as? Double ?? 0.90
        alertBatteryThreshold = defaults.object(forKey: Keys.alertBatteryThreshold) as? Double ?? 0.10
        alertOnThermal = defaults.object(forKey: Keys.alertOnThermal) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var keepRunningWithoutWindows: Bool {
        closeToMenuBar || startInMenuBar || !showInDock
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func applyLoginItem() {
        do {
            switch (launchAtLogin, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("Vitals: failed to update login item: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
