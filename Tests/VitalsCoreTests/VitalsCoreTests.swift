import Foundation
import XCTest
@testable import VitalsCore

final class VitalsCoreTests: XCTestCase {
    func testMemoryOccupancyIsNotPresentedAsPressureDiagnosis() {
        let memory = MemoryBreakdown(totalBytes: 100, wiredBytes: 40, activeBytes: 30, inactiveBytes: 25)
        let snapshot = SystemSnapshot(memory: memory)

        XCTAssertEqual(snapshot.memoryFraction, 0.95, accuracy: 0.0001)
        XCTAssertEqual(snapshot.memoryStatus.label, "Memory used")
        XCTAssertFalse(snapshot.memoryStatus.isPressureDiagnosis)
    }

    func testProcessLabelDescribesRankedSubsetRatherThanSystemTotal() {
        let snapshot = SystemSnapshot(
            topProcesses: [ProcessMetric(pid: 1, name: "one", cpuUsage: 1, memoryBytes: 1)],
            topProcessLimit: 25
        )

        XCTAssertEqual(snapshot.processListLabel, "Top 25 processes")
        XCTAssertNotEqual(snapshot.processListLabel, "1 processes")
    }

    func testShortHistoryRangeUsesActualRetainedSpan() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var history = MetricHistory()
        history.append(0.2, at: end.addingTimeInterval(-60))
        history.append(0.4, at: end)

        XCTAssertEqual(history.displayLabel(range: .oneHour, now: end), "Last 1m")
    }

    func testAlignedGridUsesStableExplicitScaleValues() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var history = MetricHistory()
        history.append(8_000, at: end)

        let values = BarTimeGrid.aligned(range: .fifteenMinutes, count: 15, now: end).averages(from: history)
        XCTAssertTrue(values.contains(8_000))
        XCTAssertEqual(values.max(), 8_000)
    }

    func testAdaptiveGridZoomsWhileHistoryIsFilling() {
        let short = BarTimeGrid.effectiveDuration(range: .oneHour, availableSpan: 49)
        XCTAssertLessThan(short, HistoryTimeRange.oneHour.duration)
        XCTAssertGreaterThanOrEqual(short, 45)

        let full = BarTimeGrid.effectiveDuration(range: .oneHour, availableSpan: 3_500)
        XCTAssertEqual(full, HistoryTimeRange.oneHour.duration)

        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var history = MetricHistory()
        for offset in stride(from: 40.0, through: 0, by: -2) {
            history.append(0.5, at: end.addingTimeInterval(-offset))
        }
        let span = history.availableSpan(range: .fifteenMinutes, now: end)
        let grid = BarTimeGrid.aligned(range: .fifteenMinutes, count: 20, now: end, availableSpan: span)
        let values = grid.averages(from: history)
        let filled = values.filter { $0 > 0 }.count
        // Zoomed window should put data across most bars, not only the last 1–2.
        XCTAssertGreaterThan(filled, 8)
        XCTAssertLessThan(grid.bucketWidth * Double(grid.bucketCount), HistoryTimeRange.fifteenMinutes.duration)
    }

    func testAlignedGridCarriesSamplesAcrossFasterChartBuckets() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var history = MetricHistory()
        history.append(0.25, at: end.addingTimeInterval(-10))
        history.append(0.75, at: end.addingTimeInterval(-5))

        let grid = BarTimeGrid.aligned(
            range: .fifteenMinutes,
            count: 45,
            now: end,
            availableSpan: 10
        )
        let values = grid.averages(from: history)
        let firstObserved = try! XCTUnwrap(values.firstIndex(where: { $0 > 0 }))

        XCTAssertFalse(values[firstObserved...].contains(0))
        XCTAssertTrue(values[firstObserved...].contains(0.25))
        XCTAssertEqual(values.last, 0.75)
    }

    func testUsageAvailabilityDistinguishesUnavailableFromNoActivity() {
        XCTAssertEqual(UsageSummary(isAvailable: false).displayStatus, "Unavailable")
        XCTAssertEqual(UsageSummary(isAvailable: true).displayStatus, "No activity today")
        XCTAssertEqual(
            UsageSummary(isAvailable: false, statusMessage: "Disabled in Settings").displayStatus,
            "Disabled in Settings"
        )
    }

    func testIncrementalScannerConsumesOnlyAppendedCompleteRecords() async throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let directory = fixture.appendingPathComponent(".codex/sessions/2026/07/10", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session.jsonl")
        let first = codexRecord(input: 100, cached: 40, output: 20, total: 120, minute: 0)
        try (first + "\n").write(to: file, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        let scanner = AIUsageScanner(homeDirectory: fixture)
        let initial = await scanner.scanToday(now: day, calendar: calendar)
        XCTAssertEqual(initial.codex.totalTokens, 120)

        let second = codexRecord(input: 160, cached: 70, output: 35, total: 195, minute: 1)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(second.utf8))
        try handle.close()
        let partial = await scanner.scanToday(now: day, calendar: calendar)
        XCTAssertEqual(partial.codex.totalTokens, 120, "partial JSONL records must not be counted")

        let newlineHandle = try FileHandle(forWritingTo: file)
        try newlineHandle.seekToEnd()
        try newlineHandle.write(contentsOf: Data("\n".utf8))
        try newlineHandle.close()
        let appended = await scanner.scanToday(now: day, calendar: calendar)
        XCTAssertEqual(appended.codex.totalTokens, 195, "only the cumulative delta should be added")
    }

    private func codexRecord(input: Int, cached: Int, output: Int, total: Int, minute: Int) -> String {
        #"{"timestamp":"2026-07-10T10:0\#(minute):00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(total)}}}}"#
    }
}
