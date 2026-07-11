import Foundation
import UserNotifications
import VitalsCore

@MainActor
final class AlertManager {
    private var lastMemoryAlert: Date?
    private var lastBatteryAlert: Date?
    private var lastThermalAlert: Date?
    private let cooldown: TimeInterval = 15 * 60
    private var authorized = false

    func prepareIfNeeded(enabled: Bool) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            do {
                authorized = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                authorized = false
            }
        default:
            authorized = false
        }
    }

    func evaluate(snapshot: SystemSnapshot, settings: AppSettings) {
        guard settings.alertsEnabled, authorized else { return }
        let now = Date()

        if snapshot.memoryFraction >= settings.alertMemoryThreshold {
            if lastMemoryAlert.map({ now.timeIntervalSince($0) > cooldown }) ?? true {
                lastMemoryAlert = now
                post(
                    id: "memory",
                    title: "High memory use",
                    body: "Memory use is at \(VitalsFormat.percent(snapshot.memoryFraction)). This is an occupancy threshold, not a macOS memory-pressure diagnosis."
                )
            }
        }

        if settings.alertOnThermal, snapshot.thermalLevel.isElevated {
            if lastThermalAlert.map({ now.timeIntervalSince($0) > cooldown }) ?? true {
                lastThermalAlert = now
                post(
                    id: "thermal",
                    title: "Thermal pressure",
                    body: "System thermal state is \(snapshot.thermalLevel.label.lowercased())."
                )
            }
        }

        if let level = snapshot.batteryLevel,
           snapshot.batteryPowerState == .onBattery,
           level <= settings.alertBatteryThreshold {
            if lastBatteryAlert.map({ now.timeIntervalSince($0) > cooldown }) ?? true {
                lastBatteryAlert = now
                post(
                    id: "battery",
                    title: "Low battery",
                    body: "Battery is at \(VitalsFormat.percent(level))."
                )
            }
        }
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "vitals.\(id).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
