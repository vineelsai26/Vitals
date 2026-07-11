import Foundation

public enum VitalsFormat {
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    public static func rate(_ value: Double) -> String {
        guard value >= 1 else { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }

    public static func compactTokens(_ value: UInt64) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    public static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public static func axisTime(_ date: Date, span: TimeInterval) -> String {
        if span >= 36 * 3_600 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        if span >= 6 * 3_600 {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Shared ceiling ladder for throughput charts, so every surface that plots
/// the same rate series agrees on scale and the ceiling steps between round
/// values instead of continuously rubber-banding to the latest peak.
public enum RateScale {
    public static let tiers: [Double] = [
        256_000, 1_000_000, 5_000_000, 10_000_000, 25_000_000,
        50_000_000, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000,
    ]

    /// Smallest tier that contains `peak` (minimum 1 MB/s so idle traffic
    /// doesn't stretch to full height); rounds up in whole GB/s beyond the ladder.
    public static func ceiling(for peak: Double) -> Double {
        let floored = max(peak, 0)
        return tiers.first(where: { $0 >= floored && $0 >= 1_000_000 })
            ?? (floored / 1_000_000_000).rounded(.up) * 1_000_000_000
    }
}
