import AppKit
import SwiftUI
import VitalsCore
import VKit

struct DashboardCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: VRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VRadius.card, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            }
    }

    private var cardFill: Color {
        colorScheme == .dark ? Palette.surface : Color.white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.095)
    }
}

/// How a sparkline maps values to height. There is deliberately no
/// self-normalizing mode: flat series must read as flat.
enum SparklineScale {
    /// Absolute 0…1 domain for percent-like metrics.
    case unit
    /// 0…ceiling domain for byte rates; pass a shared `RateScale` ceiling.
    case rate(ceiling: Double)
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color
    var scale: SparklineScale = .unit
    /// Soft gradient fill under the line.
    var fill: Bool = false

    var body: some View {
        GeometryReader { geometry in
            if values.count < 2 {
                // Cold start: honest dashed baseline, not a fabricated flat line.
                Path { path in
                    let y = geometry.size.height - 1
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                let points = scaledPoints(in: geometry.size)
                ZStack {
                    if fill, let first = points.first, let last = points.last {
                        Path { path in
                            path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                            points.forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func scaledPoints(in size: CGSize) -> [CGPoint] {
        let ceiling: Double
        switch scale {
        case .unit:
            ceiling = 1
        case .rate(let value):
            ceiling = max(value, 1)
        }
        // Inset the stroke so extremes are not clipped by the frame.
        let inset: CGFloat = 1
        let usable = max(size.height - inset * 2, 1)
        return values.enumerated().map { index, value in
            let fraction = min(max(value / ceiling, 0), 1)
            return CGPoint(
                x: CGFloat(index) / CGFloat(max(values.count - 1, 1)) * size.width,
                y: inset + usable - CGFloat(fraction) * usable
            )
        }
    }
}

struct CompactMetricCard: View {
    enum Kind {
        case percent
        case rate
    }

    let title: String
    let value: String
    let detailLabel: String
    let detailValue: String
    let history: [Double]
    let tint: Color
    var kind: Kind = .percent
    var rateCeiling: Double = 1
    var helpText: String? = nil

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(VText.bodyStrong)
                Text(value)
                    .font(VText.metricL)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Sparkline(
                    values: history,
                    tint: tint,
                    scale: kind == .percent ? .unit : .rate(ceiling: rateCeiling),
                    fill: true
                )
                .frame(height: 30)
                .accessibilityLabel(accessibilitySummary)
                HStack {
                    Text(detailLabel)
                    Spacer(minLength: 4)
                    Text(detailValue).monospacedDigit()
                }
                .font(VText.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(minWidth: 125, minHeight: 116)
        .help(helpText ?? "\(title): \(value). \(detailLabel) \(detailValue)")
    }

    private var accessibilitySummary: String {
        guard let last = history.last else { return "\(title) recent activity unavailable" }
        switch kind {
        case .percent:
            let avg = history.reduce(0, +) / Double(max(history.count, 1))
            return "\(title) average \(VitalsFormat.percent(avg)), latest \(VitalsFormat.percent(last)) over \(history.count) samples"
        case .rate:
            return "\(title) latest \(VitalsFormat.rate(last)) over \(history.count) samples"
        }
    }
}

struct MultiLineChart: View {
    let series: [(values: [Double], color: Color, unitScale: ChartScale)]
    /// Shared rate ceiling; pass `RateScale.ceiling(for:)` of the peak across
    /// every rate series shown together so surfaces agree.
    var rateCeiling: Double = 1_000_000

    enum ChartScale {
        case unit
        case rate
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Divider().opacity(0.30)
                        Spacer()
                    }
                }
                ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                    chartPath(
                        values: item.values,
                        scale: item.unitScale,
                        ratePeak: rateCeiling,
                        size: geometry.size
                    )
                        .stroke(item.color, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func chartPath(values: [Double], scale: ChartScale, ratePeak: Double, size: CGSize) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let normalized: [Double]
        switch scale {
        case .unit:
            normalized = values.map { min(max($0, 0), 1) }
        case .rate:
            normalized = values.map { min(max($0 / max(ratePeak, 1), 0), 1) }
        }
        for (index, value) in normalized.enumerated() {
            let point = CGPoint(
                x: CGFloat(index) / CGFloat(max(normalized.count - 1, 1)) * size.width,
                y: (1 - CGFloat(value)) * size.height
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

struct StatusBanner: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
            Text(message)
                .font(VText.caption)
            Spacer()
        }
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isError ? Color.orange : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.chip + 2))
    }
}
