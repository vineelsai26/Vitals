import SwiftUI
import VKit

/// Vitals type ramp. Seven tokens, no ad-hoc `.system(size:)` literals in views.
/// Floor rule: nothing below `caption` (11) for persistent UI text; `micro` is
/// reserved for in-plot annotations like scale captions.
enum VText {
    /// Page titles ("Overview", "AI Usage").
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    /// Hero metric values (strip cells, provider totals).
    static let metricL = Font.system(size: 22, weight: .semibold, design: .rounded)
    /// Mid metric values (lane columns, card headlines).
    static let metricM = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Default reading size (rows, table cells).
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Secondary metadata (hints, details, legends).
    static let caption = Font.system(size: 11)
    static let captionStrong = Font.system(size: 11, weight: .medium)
    /// Uppercase section labels — pair with `.kicker()`.
    static let kickerFont = Font.system(size: 11, weight: .semibold)
    /// Chart scale captions only ("0–5 MB/s").
    static let micro = Font.system(size: 9, weight: .medium)
}

extension View {
    /// Uppercase tracked section label ("CPU", "MACHINE", "TOP BY MEMORY").
    func kicker(_ color: Color = .secondary) -> some View {
        font(VText.kickerFont)
            .foregroundStyle(color)
            .textCase(.uppercase)
            .tracking(0.6)
            .lineLimit(1)
    }
}

/// Metric colors as fill/text pairs. Fills are for chart marks and capsules;
/// text variants pass ≥4.5:1 on both canvas colors for sizes under 17 pt.
/// Hue rules: one blue (CPU = brand accent, Codex aliases it), network is
/// teal, upload/Claude share purple, memory owns orange, amber = swap only,
/// red = thermal only.
enum VitalsColor {
    // CPU — the one blue (brand accent).
    static let cpu = Palette.accent
    static let cpuText = Color(lightHex: 0x0064C8, darkHex: 0x64A8F0)

    // Network download — teal.
    static let network = Color(lightHex: 0x0E9BA4, darkHex: 0x2FB8C0)
    static let networkText = Color(lightHex: 0x00727C, darkHex: 0x45C4CC)

    // Upload — purple.
    static let upload = Color(lightHex: 0x7A3FE4, darkHex: 0x9B6CF5)
    static let uploadText = Color(lightHex: 0x6527CE, darkHex: 0xB08CF8)

    // Memory — orange.
    static let memory = Color(lightHex: 0xFF5C0A, darkHex: 0xFF6B24)
    static let memoryText = Color(lightHex: 0xBC3E00, darkHex: 0xFF8A50)

    // Memory composition — single-hue orange ramp, wired darkest.
    static let memoryWired = Color(lightHex: 0xB33A00, darkHex: 0xC2521A)
    static let memoryActive = Color(lightHex: 0xE8600D, darkHex: 0xF0742E)
    static let memoryInactive = Color(lightHex: 0xF59B57, darkHex: 0xE8A76A)
    static let memoryCompressed = Color(lightHex: 0x9C8AA8, darkHex: 0x8E7F9E)
    /// Legend swatch for free memory; the bar itself renders free as a track.
    static let memoryFree = Palette.muted

    // Swap — amber, the only amber in the app.
    static let memorySwap = Color(lightHex: 0xE8A20C, darkHex: 0xF0B429)
    static let memorySwapText = Color(lightHex: 0x8F5A00, darkHex: 0xE8B54A)

    // Battery — green.
    static let battery = Color(lightHex: 0x1C8C40, darkHex: 0x2EA855)
    static let batteryText = Color(lightHex: 0x14733A, darkHex: 0x4CC470)

    // Disk — steel blue-gray, low emphasis.
    static let disk = Color(lightHex: 0x46708E, darkHex: 0x7FA5C0)
    static let diskText = Color(lightHex: 0x3A607C, darkHex: 0x93B4CC)

    // Thermal — the only red.
    static let thermal = Color(lightHex: 0xD93A1F, darkHex: 0xE85C42)
    static let thermalText = Color(lightHex: 0xB32E14, darkHex: 0xF06A50)

    // AI providers alias the series pair: Codex = series-A blue, Claude = purple.
    static let codex = cpu
    static let codexText = cpuText
    static let claude = upload
    static let claudeText = uploadText
}

/// Corner-radius tokens (continuous curvature at call sites).
enum VRadius {
    static let control: CGFloat = 5
    static let chip: CGFloat = 6
    static let card: CGFloat = 10
    static let field: CGFloat = 12
}
