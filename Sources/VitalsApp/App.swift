import AppKit
import SwiftUI
import VitalsUI

final class VitalsAppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        VitalsAppSupport.applyActivationPolicy()
        DispatchQueue.main.async {
            if VitalsAppSupport.startInMenuBar {
                NSApplication.shared.windows.filter { $0.canBecomeMain }.forEach { $0.close() }
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !VitalsAppSupport.keepRunningWithoutWindows
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
    @StateObject private var runtime = VitalsRuntime()

    var body: some Scene {
        Window("Vitals", id: "main") {
            VitalsMainView(runtime: runtime)
                .preferredColorScheme(runtime.colorScheme)
                .frame(minWidth: 900, minHeight: 480)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    appDelegate.reopenMainWindow = { openWindow(id: "main") }
                    runtime.start()
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
                        runtime.selection = section
                        openMainWindow()
                    }
                    .keyboardShortcut(section.shortcutKey ?? "0", modifiers: [.command])
                }
            }
            CommandGroup(after: .toolbar) {
                Button(runtime.isRunning ? "Pause Monitoring" : "Resume Monitoring") {
                    runtime.toggleRunning()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Refresh Now") {
                    runtime.refreshNow()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            VitalsMenuBarContent(runtime: runtime)
                .preferredColorScheme(runtime.colorScheme)
                .onAppear { runtime.start() }
        } label: {
            VitalsMenuBarLabel(runtime: runtime)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VitalsSettingsContent(runtime: runtime)
                .preferredColorScheme(runtime.colorScheme)
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
            VitalsRenderHarness.run()
        } else {
            VitalsApplication.main()
        }
    }
}
