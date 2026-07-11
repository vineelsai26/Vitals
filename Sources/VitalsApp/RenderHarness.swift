import AppKit
import SwiftUI

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
        guard ["light", "dark"].contains(appearance), ["main", "menu", "menu-ai"].contains(surface) else {
            fail("appearance must be light|dark and surface must be main|menu|menu-ai")
        }

        let settings = AppSettings.shared
        let controller = MonitorController.demo(settings: settings)
        let scheme: ColorScheme = appearance == "dark" ? .dark : .light
        let canvasColor = appearance == "dark"
            ? Color(red: 0.075, green: 0.075, blue: 0.08)
            : Color.white
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
        } else {
            rendered = AnyView(
                MainAppLayout(
                    selection: .constant(.overview),
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

        let renderer = ImageRenderer(content: rendered)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
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

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(2)
    }
}
