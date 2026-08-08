import Combine
import SwiftUI
import VitalsCore

// Public embedding API for Vitals. The view/controller types stay internal;
// consumers (the standalone VitalsApp and the PowerTools suite) talk only to
// these wrappers, so Vitals can run standalone or embedded in another app
// without exposing its whole view graph.

/// Owns one Vitals instance's monitor + settings. Create one and hand it to
/// the views below. Safe to have several (standalone app vs. embedded), though
/// each runs its own sampler.
@MainActor
public final class VitalsRuntime: ObservableObject {
    let controller: MonitorController
    let settings: AppSettings
    @Published public var selection: DashboardSection = .overview
    private var forwards: Set<AnyCancellable> = []

    public init() {
        self.settings = .shared
        self.controller = MonitorController()
        // Views and scenes observe the runtime but read through to the
        // controller/settings (isRunning, colorScheme, …), so their changes
        // must republish here or that state goes stale.
        controller.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &forwards)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &forwards)
    }

    public func start() { controller.start() }
    /// Pause sampling when embedded and the tool is disabled.
    public func pause() { if controller.isRunning { controller.toggleRunning() } }
    public func refreshNow() { controller.refreshNow() }
    public func toggleRunning() { controller.toggleRunning() }
    public var isRunning: Bool { controller.isRunning }
    public var colorScheme: ColorScheme? { settings.appearance.colorScheme }
}

/// App-lifecycle helpers used by the standalone app delegate, without
/// exposing `AppSettings`.
@MainActor
public enum VitalsAppSupport {
    public static func applyActivationPolicy() { AppSettings.shared.applyActivationPolicy() }
    public static var startInMenuBar: Bool { AppSettings.shared.startInMenuBar }
    public static var keepRunningWithoutWindows: Bool { AppSettings.shared.keepRunningWithoutWindows }
}

/// The main dashboard. Does not set a color scheme, so an embedding host keeps
/// control of appearance; the standalone app sets it on the scene.
public struct VitalsMainView: View {
    @ObservedObject private var runtime: VitalsRuntime

    public init(runtime: VitalsRuntime) { self.runtime = runtime }

    public var body: some View {
        MainAppLayout(
            selection: $runtime.selection,
            scrollsContent: true,
            showsPreviewTrafficLights: false
        )
        .environmentObject(runtime.controller)
        .environmentObject(runtime.settings)
    }
}

/// The menu-bar dashboard panel.
public struct VitalsMenuBarContent: View {
    @ObservedObject private var runtime: VitalsRuntime

    public init(runtime: VitalsRuntime) { self.runtime = runtime }

    public var body: some View {
        MenuBarView()
            .environmentObject(runtime.controller)
            .environmentObject(runtime.settings)
    }
}

/// The menu-bar label (icon + optional live metric text).
public struct VitalsMenuBarLabel: View {
    @ObservedObject private var runtime: VitalsRuntime

    public init(runtime: VitalsRuntime) { self.runtime = runtime }

    public var body: some View {
        Label {
            MenuBarLabelText()
                .environmentObject(runtime.controller)
                .environmentObject(runtime.settings)
        } icon: {
            Image(systemName: "waveform.path.ecg")
        }
    }
}

/// Settings-window content.
public struct VitalsSettingsContent: View {
    @ObservedObject private var runtime: VitalsRuntime

    public init(runtime: VitalsRuntime) { self.runtime = runtime }

    public var body: some View {
        SettingsView()
            .environmentObject(runtime.settings)
            .environmentObject(runtime.controller)
    }
}

/// `--render-ui` screenshot harness entry point.
@MainActor
public enum VitalsRenderHarness {
    public static func run() { RenderHarness.run() }
}
