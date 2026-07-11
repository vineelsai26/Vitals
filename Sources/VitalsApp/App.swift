import AppKit
import SwiftUI
import VitalsCore

final class VitalsAppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        settings.applyActivationPolicy()
        DispatchQueue.main.async {
            if settings.startInMenuBar {
                NSApplication.shared.windows.filter { $0.canBecomeMain }.forEach { $0.close() }
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.shared.keepRunningWithoutWindows
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        if let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            reopenMainWindow?()
        }
        return true
    }
}

struct VitalsApplication: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(VitalsAppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var controller = MonitorController()
    @State private var selection: DashboardSection = .overview

    var body: some Scene {
        Window("Vitals", id: "main") {
            MainAppLayout(
                selection: $selection,
                scrollsContent: true,
                showsPreviewTrafficLights: false
            )
            .environmentObject(controller)
            .environmentObject(settings)
            .preferredColorScheme(settings.appearance.colorScheme)
            .frame(minWidth: 900, minHeight: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                appDelegate.reopenMainWindow = { openWindow(id: "main") }
                controller.start()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_180, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navigate") {
                ForEach(DashboardSection.allCases) { section in
                    Button(section.rawValue) {
                        selection = section
                        openMainWindow()
                    }
                    .keyboardShortcut(section.shortcutKey ?? "0", modifiers: [.command])
                }
            }
            CommandGroup(after: .toolbar) {
                Button(controller.isRunning ? "Pause Monitoring" : "Resume Monitoring") {
                    controller.toggleRunning()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Refresh Now") {
                    controller.refreshNow()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(controller)
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onAppear { controller.start() }
        } label: {
            Label {
                MenuBarLabelText()
                    .environmentObject(controller)
                    .environmentObject(settings)
            } icon: {
                Image(systemName: "waveform.path.ecg")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(controller)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

@main
enum AppMain {
    static func main() {
        if CommandLine.arguments.contains("--render-ui") {
            RenderHarness.run()
        } else {
            VitalsApplication.main()
        }
    }
}
