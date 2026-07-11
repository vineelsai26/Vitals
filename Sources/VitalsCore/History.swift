import Foundation

public enum HistoryTimeRange: String, CaseIterable, Identifiable, Sendable, Codable {
    case fifteenMinutes = "15M"
    case oneHour = "1H"
    case sixHours = "6H"
    case twentyFourHours = "24H"
    case sevenDays = "7D"
    case thirtyDays = "30D"

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 3_600
        case .sixHours: return 6 * 3_600
        case .twentyFourHours: return 24 * 3_600
        case .sevenDays: return 7 * 24 * 3_600
        case .thirtyDays: return 30 * 24 * 3_600
        }
    }

    /// Target spacing used when downsampling older data for this window.
    public var preferredSampleInterval: TimeInterval {
        switch self {
        case .fifteenMinutes: return 2
        case .oneHour: return 5
        case .sixHours: return 30
        case .twentyFourHours: return 120
        case .sevenDays: return 900
        case .thirtyDays: return 3_600
        }
    }
}

public struct MetricSample: Sendable, Equatable, Codable {
    public var at: Date
    public var value: Double

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

/// Timestamped ring buffer with age-based retention and downsampling.
public struct MetricHistory: Sendable, Equatable, Codable {
    public private(set) var samples: [MetricSample]
    public var maxSamples: Int
    public var maxAge: TimeInterval

    public init(
        samples: [MetricSample] = [],
        maxSamples: Int = 3_600,
        maxAge: TimeInterval = HistoryTimeRange.thirtyDays.duration
    ) {
        self.samples = samples
        self.maxSamples = maxSamples
        self.maxAge = maxAge
    }

    public var isEmpty: Bool { samples.isEmpty }

    public mutating func append(_ value: Double, at date: Date = Date()) {
        if let last = samples.last, date < last.at { return }
        // Coalesce samples that arrive faster than 1s for long-running stability.
        if let last = samples.last, date.timeIntervalSince(last.at) < 0.9 {
            samples[samples.count - 1] = MetricSample(at: date, value: value)
        } else {
            samples.append(MetricSample(at: date, value: value))
        }
        trim(now: date)
    }

    public mutating func replaceAll(_ values: [Double], spacing: TimeInterval = 2, endingAt end: Date = Date()) {
        samples = values.enumerated().map { index, value in
            let offset = spacing * Double(values.count - 1 - index)
            return MetricSample(at: end.addingTimeInterval(-offset), value: value)
        }
        trim(now: end)
    }

    public func window(range: HistoryTimeRange, now: Date = Date()) -> [MetricSample] {
        let cutoff = now.addingTimeInterval(-range.duration)
        let filtered = samples.filter { $0.at >= cutoff }
        return downsample(filtered, interval: range.preferredSampleInterval)
    }

    public func values(range: HistoryTimeRange, now: Date = Date()) -> [Double] {
        window(range: range, now: now).map(\.value)
    }

    /// Split the selected range into `count` equal **epoch-aligned** time buckets and
    /// return the average sample in each (left = oldest). Empty buckets are 0.
    ///
    /// Bucket boundaries are aligned to absolute time (`floor(t / Δ) * Δ`) so every
    /// metric series shares the same bar slots. When the clock crosses a boundary,
    /// a new bar appears on the right for all charts at once.
    public func bucketedAverages(
        range: HistoryTimeRange,
        count: Int,
        now: Date = Date()
    ) -> [Double] {
        BarTimeGrid.aligned(range: range, count: count, now: now).averages(from: self)
    }

    /// Duration represented by one bar when using `bucketedAverages`.
    public static func barDuration(range: HistoryTimeRange, count: Int) -> TimeInterval {
        BarTimeGrid.aligned(range: range, count: count, now: Date()).bucketWidth
    }

    /// Actual span of retained samples in the requested window (may be shorter than range).
    public func availableSpan(range: HistoryTimeRange, now: Date = Date()) -> TimeInterval? {
        let filtered = samples.filter { $0.at >= now.addingTimeInterval(-range.duration) }
        guard let first = filtered.first?.at, let last = filtered.last?.at, last > first else { return nil }
        return last.timeIntervalSince(first)
    }

    public func displayLabel(range: HistoryTimeRange, now: Date = Date()) -> String {
        guard let span = availableSpan(range: range, now: now) else {
            return "Waiting for samples"
        }
        if span >= range.duration * 0.9 {
            return range.label
        }
        return "Last \(VitalsFormat.duration(span))"
    }

    public func timeAxisLabels(range: HistoryTimeRange, now: Date = Date(), count: Int = 5) -> [Date] {
        let windowed = window(range: range, now: now)
        guard let first = windowed.first?.at, let last = windowed.last?.at, last > first else {
            return (0..<count).map { index in
                let fraction = Double(index) / Double(max(count - 1, 1))
                return now.addingTimeInterval(-range.duration * (1 - fraction))
            }
        }
        return (0..<count).map { index in
            let fraction = Double(index) / Double(max(count - 1, 1))
            return first.addingTimeInterval(last.timeIntervalSince(first) * fraction)
        }
    }

    private mutating func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-maxAge)
        if let firstKeep = samples.firstIndex(where: { $0.at >= cutoff }), firstKeep > 0 {
            samples.removeFirst(firstKeep)
        } else if samples.last?.at ?? now < cutoff {
            samples.removeAll()
        }
        while samples.count > maxSamples {
            downsampleInPlace(factor: 2)
        }
    }

    private mutating func downsampleInPlace(factor: Int) {
        guard factor > 1, samples.count > 2 else {
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
            return
        }
        var compacted: [MetricSample] = []
        compacted.reserveCapacity(samples.count / factor + 1)
        var index = 0
        while index < samples.count {
            let end = min(index + factor, samples.count)
            let slice = samples[index..<end]
            let avg = slice.map(\.value).reduce(0, +) / Double(slice.count)
            let at = slice[slice.index(before: slice.endIndex)].at
            compacted.append(MetricSample(at: at, value: avg))
            index = end
        }
        samples = compacted
    }

    private func downsample(_ input: [MetricSample], interval: TimeInterval) -> [MetricSample] {
        guard input.count > 2, interval > 0 else { return input }
        var result: [MetricSample] = []
        result.reserveCapacity(min(input.count, 240))
        var bucketStart = input[0].at
        var bucketValues: [Double] = []
        var bucketEnd = input[0].at

        func flush() {
            guard !bucketValues.isEmpty else { return }
            let avg = bucketValues.reduce(0, +) / Double(bucketValues.count)
            result.append(MetricSample(at: bucketEnd, value: avg))
            bucketValues.removeAll(keepingCapacity: true)
        }

        for sample in input {
            if sample.at.timeIntervalSince(bucketStart) >= interval, !bucketValues.isEmpty {
                flush()
                bucketStart = sample.at
            }
            bucketValues.append(sample.value)
            bucketEnd = sample.at
        }
        flush()
        return result
    }
}

/// Shared time grid for overview bar charts so CPU / memory / swap / network stay in lockstep.
public struct BarTimeGrid: Sendable, Equatable {
    public let bucketWidth: TimeInterval
    public let bucketCount: Int
    /// Start of the oldest bar (left).
    public let windowStart: Date
    /// Exclusive end of the newest bar (right); always ≥ now.
    public let windowEnd: Date
    public let now: Date

    /// Build an epoch-aligned grid of `count` buckets ending with the in-progress bucket that contains `now`.
    ///
    /// When `availableSpan` is shorter than the selected range (history still filling),
    /// the grid zooms to that span so bars fill the chart instead of leaving a left void.
    public static func aligned(
        range: HistoryTimeRange,
        count: Int,
        now: Date = Date(),
        availableSpan: TimeInterval? = nil
    ) -> BarTimeGrid {
        let n = max(count, 1)
        let duration = effectiveDuration(range: range, availableSpan: availableSpan)
        let width = max(duration / Double(n), 0.25)
        let nowTs = now.timeIntervalSince1970
        // Current incomplete bucket: [floor(now/Δ)*Δ, floor(now/Δ)*Δ + Δ)
        let currentStartTs = floor(nowTs / width) * width
        let windowEndTs = currentStartTs + width
        let windowStartTs = windowEndTs - Double(n) * width
        return BarTimeGrid(
            bucketWidth: width,
            bucketCount: n,
            windowStart: Date(timeIntervalSince1970: windowStartTs),
            windowEnd: Date(timeIntervalSince1970: windowEndTs),
            now: now
        )
    }

    /// Prefer the selected range once history is mostly filled; otherwise zoom to retained span.
    public static func effectiveDuration(
        range: HistoryTimeRange,
        availableSpan: TimeInterval?
    ) -> TimeInterval {
        let full = range.duration
        guard let available = availableSpan, available > 0 else { return full }
        // Keep a small pad past the newest sample so the live bar has room to grow.
        let padded = available * 1.08
        // Don't zoom below 45s — avoids frantic 1-second bars on cold start.
        let floor: TimeInterval = 45
        if padded >= full * 0.88 { return full }
        return min(full, max(floor, padded))
    }

    public func bucketStart(at index: Int) -> Date {
        windowStart.addingTimeInterval(Double(index) * bucketWidth)
    }

    public func bucketEnd(at index: Int) -> Date {
        windowStart.addingTimeInterval(Double(index + 1) * bucketWidth)
    }

    /// Average samples in each bucket, carrying the latest observation through
    /// buckets between refreshes. Time-series samples describe the measured
    /// level until the next sample arrives; treating those buckets as zero
    /// creates artificial gaps whenever the chart bucket is narrower than the
    /// collection cadence.
    public func averages(from history: MetricHistory) -> [Double] {
        let samples = history.samples
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: bucketCount)
        }

        var result = Array(repeating: 0.0, count: bucketCount)
        var sampleIndex = 0
        var latestValue: Double?
        let n = samples.count

        // A sample before the window remains the latest known level at its start.
        while sampleIndex < n, samples[sampleIndex].at < windowStart {
            latestValue = samples[sampleIndex].value
            sampleIndex += 1
        }

        for bucket in 0..<bucketCount {
            let start = bucketStart(at: bucket)
            let end = bucketEnd(at: bucket)

            while sampleIndex < n, samples[sampleIndex].at < start {
                sampleIndex += 1
            }

            var sum = 0.0
            var seen = 0
            var cursor = sampleIndex
            while cursor < n {
                let at = samples[cursor].at
                if at >= end { break }
                // Ignore samples after "now" (shouldn't exist, but keep deterministic).
                if at > now { break }
                sum += samples[cursor].value
                seen += 1
                cursor += 1
            }
            if seen > 0 {
                result[bucket] = sum / Double(seen)
                latestValue = samples[cursor - 1].value
            } else if start <= now, let latestValue {
                result[bucket] = latestValue
            }
            sampleIndex = cursor
        }
        return result
    }

    /// Average each history with the **same** grid (shared wall-clock buckets).
    public func averages(from histories: [MetricHistory]) -> [[Double]] {
        histories.map { averages(from: $0) }
    }
}
