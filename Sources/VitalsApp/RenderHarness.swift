import AppKit
import SwiftUI
import VKit

enum RenderHarness {
    @MainActor
    static func run() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-ui"), index + 1 < arguments.count else {
            fail("usage: --render-ui <out.png> [--appearance light|dark] [--surface main|menu]")
        }
        let outputPath = arguments[index + 1]
        let appearance = value(after: "--appearance", in: arguments) ?? "light"
        let surface = value(after: "--surface", in: arguments) ?? "main"
        let sectionName = value(after: "--section", in: arguments) ?? "overview"
        let sections: [String: DashboardSection] = [
            "overview": .overview,
            "ai": .aiUsage,
            "processes": .processes,
            "network": .network,
            "storage": .storage,
        ]
        guard ["light", "dark"].contains(appearance),
              ["main", "menu", "menu-ai", "settings"].contains(surface),
              let section = sections[sectionName] else {
            fail("appearance must be light|dark, surface main|menu|menu-ai|settings, section overview|ai|processes|network|storage")
        }

        let settings = AppSettings.shared
        let controller = MonitorController.demo(settings: settings)
        let scheme: ColorScheme = appearance == "dark" ? .dark : .light
        let canvasColor = Palette.background
        NSApplication.shared.appearance = NSAppearance(
            named: appearance == "dark" ? .darkAqua : .aqua
        )

        let rendered: AnyView
        if surface == "menu" || surface == "menu-ai" {
            rendered = AnyView(
                MenuBarView(initialPanel: surface == "menu-ai" ? .aiUsage : .system)
                    .environmentObject(controller)
                    .environmentObject(settings)
                    .environment(\.colorScheme, scheme)
                    .preferredColorScheme(scheme)
                    .fixedSize()
            )
        } else if surface == "settings" {
            rendered = AnyView(
                SettingsView()
                    .environmentObject(controller)
                    .environmentObject(settings)
                    .environment(\.colorScheme, scheme)
                    .preferredColorScheme(scheme)
                    .frame(width: 520, height: 700)
                    .background(canvasColor)
            )
        } else {
            rendered = AnyView(
                MainAppLayout(
                    selection: .constant(section),
                    scrollsContent: false,
                    showsPreviewTrafficLights: true
                )
                    .environmentObject(controller)
                    .environmentObject(settings)
                    .environment(\.colorScheme, scheme)
                    .preferredColorScheme(scheme)
                    .frame(width: 1_180, height: 640)
                    .background(canvasColor)
            )
        }

        let fixedSize: CGSize?
        switch surface {
        case "menu", "menu-ai":
            fixedSize = nil // self-sizing popover
        case "settings":
            fixedSize = CGSize(width: 520, height: 700)
        default:
            fixedSize = CGSize(width: 1_180, height: 640)
        }
        guard let png = captureOffscreen(
            rendered,
            size: fixedSize,
            appearance: NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        ) else {
            fail("render failed")
        }

        do {
            try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("rendered \(outputPath)")
            exit(0)
        } catch {
            fail("write failed: \(error)")
        }
    }

    /// Renders inside a real (off-screen) window so AppKit-backed controls —
    /// grouped Forms, text fields, pickers — rasterize correctly. SwiftUI's
    /// ImageRenderer draws those as blanks or placeholder glyphs.
    @MainActor
    private static func captureOffscreen(
        _ content: AnyView,
        size: CGSize?,
        appearance: NSAppearance?
    ) -> Data? {
        let hosting = NSHostingView(rootView: content)
        if let size {
            // Fixed-size surfaces: stop the hosting view from driving window
            // size (it under-measures fixed-frame layouts and re-sizes the
            // window mid-runloop, center-clipping the capture).
            hosting.sizingOptions = []
            hosting.frame.size = size
        } else {
            // Self-sizing surfaces (menu popover) need sizingOptions intact
            // for fittingSize to measure at all.
            hosting.frame.size = hosting.fittingSize
        }
        guard hosting.frame.width > 1, hosting.frame.height > 1 else { return nil }

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.colorSpace = .sRGB
        window.contentView = hosting
        // Far off every display: participates in layout/appearance without
        // ever being visible.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)

        // Let onAppear handlers and async @State settle before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let size {
            window.setContentSize(size)
            hosting.frame = CGRect(origin: .zero, size: size)
        }
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)
        return rep.representation(using: .png, properties: [:])
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(2)
    }
}
