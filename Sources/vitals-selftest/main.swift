import Foundation
import VitalsCore

struct SelfTest {
    private(set) var passed = 0
    private(set) var failed = 0

    mutating func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            passed += 1
            print("PASS  \(name)")
        } else {
            failed += 1
            print("FAIL  \(name)")
        }
    }
}

@main
enum Main {
    static func main() async {
        var test = SelfTest()

        let previousCPU = CPUTicks(user: 20, system: 10, nice: 0, idle: 70)
        let currentCPU = CPUTicks(user: 40, system: 20, nice: 0, idle: 140)
        test.check(abs(CPUTicks.utilization(previous: previousCPU, current: currentCPU) - 0.3) < 0.0001, "CPU tick delta")
        test.check(CPUTicks.utilization(previous: currentCPU, current: previousCPU) == 0, "CPU reset is safe")

        let rates = NetworkCounters.rates(
            previous: NetworkCounters(receivedBytes: 1_000, sentBytes: 2_000),
            current: NetworkCounters(receivedBytes: 3_000, sentBytes: 3_000),
            elapsed: 2
        )
        test.check(rates.download == 1_000 && rates.upload == 500, "network counter rate")
        test.check(VitalsFormat.percent(0.426) == "43%", "percent formatting")
        test.check(VitalsFormat.compactTokens(42_300) == "42.3K", "token formatting")
        test.check(VitalsFormat.duration(45) == "45s", "short duration formatting")
        test.check(SystemSnapshot.demo.memoryFraction > 0.5, "snapshot derived memory fraction")
        test.check(SystemSnapshot.demo.batteryPowerState == .onBattery, "demo battery state")

        var history = MetricHistory(maxSamples: 100, maxAge: 3_600)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<60 {
            history.append(Double(index) / 100, at: start.addingTimeInterval(Double(index) * 2))
        }
        let window = history.window(range: .fifteenMinutes, now: start.addingTimeInterval(120))
        test.check(!window.isEmpty, "history window non-empty")
        test.check(history.values(range: .oneHour, now: start.addingTimeInterval(120)).count >= 10, "history values for range")
        let label = history.displayLabel(range: .oneHour, now: start.addingTimeInterval(120))
        test.check(label.contains("Last") || label == "1H", "honest range label when span is short: \(label)")

        // Equal-time buckets: 10 bars over 100s of 1.0 samples → only last bar non-zero if window is 15M?
        // Build 60s of value 1.0 ending at `end`, bucket into 6 bars over 60s range... use oneHour with dense samples.
        var bucketHistory = MetricHistory(maxSamples: 1_000, maxAge: 3_600)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        // 60 samples over last 60 seconds, value = 1.0 for second half only (last 30s)
        for index in 0..<60 {
            let at = end.addingTimeInterval(Double(index - 59))
            let value = index >= 30 ? 1.0 : 0.0
            bucketHistory.append(value, at: at)
        }
        // Use a synthetic range: bucket against oneHour but only last minute has data.
        // Prefer direct unit test of 6 equal buckets over exactly 60s of samples by using fifteenMinutes
        // and samples only in the last 60s of a 15-minute window — first buckets empty.
        let buckets = bucketHistory.bucketedAverages(range: .fifteenMinutes, count: 15, now: end)
        test.check(buckets.count == 15, "bucket count matches bar count")
        // With epoch-aligned 60s buckets over 15m, last ~60s of samples land in the final bucket(s).
        let last = buckets[14]
        test.check(last > 0.0 || buckets.contains(where: { $0 > 0 }), "recent samples appear in aligned buckets: last=\(last)")
        test.check(
            abs(BarTimeGrid.aligned(range: .fifteenMinutes, count: 15, now: end).bucketWidth - 60) < 0.001,
            "bar duration is range/count"
        )

        // Shared grid: two histories, same now → identical empty/full slot pattern when samples share timestamps.
        var hCPU = MetricHistory(maxSamples: 200, maxAge: 3_600)
        var hMem = MetricHistory(maxSamples: 200, maxAge: 3_600)
        let syncEnd = Date(timeIntervalSince1970: 1_900_000_000)
        for index in 0..<20 {
            let at = syncEnd.addingTimeInterval(Double(index - 19) * 3)
            hCPU.append(0.5, at: at)
            hMem.append(0.8, at: at)
        }
        let grid = BarTimeGrid.aligned(range: .fifteenMinutes, count: 30, now: syncEnd)
        let cpuBars = grid.averages(from: hCPU)
        let memBars = grid.averages(from: hMem)
        test.check(cpuBars.count == memBars.count, "synced series share bar count")
        let cpuMask = cpuBars.map { $0 > 0 }
        let memMask = memBars.map { $0 > 0 }
        test.check(cpuMask == memMask, "synced series share the same non-empty bar slots")

        let codexLine = Data(#"{"timestamp":"2026-07-10T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":80,"output_tokens":30,"total_tokens":150}}}}"#.utf8)
        let codex = AIUsageScanner.parseCodexLine(codexLine)
        test.check(codex?.inputTokens == 120 && codex?.totalTokens == 150, "Codex token event parser")

        let claudeLine = Data(#"{"type":"assistant","timestamp":"2026-07-10T12:00:00.000Z","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":30,"cache_creation_input_tokens":20}}}"#.utf8)
        let claude = AIUsageScanner.parseClaudeLine(claudeLine)
        test.check(claude?.cachedTokens == 50 && claude?.totalTokens == 65, "Claude usage parser")
        test.check(claude?.recordID == "msg_1", "Claude deduplication key")

        do {
            let fixture = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitals-selftest-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: fixture) }
            let codexDirectory = fixture.appendingPathComponent(".codex/sessions/2026/07/10", isDirectory: true)
            let claudeDirectory = fixture.appendingPathComponent(".claude/projects/project", isDirectory: true)
            try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

            let codexFixture = [
                #"{"timestamp":"2026-07-10T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"total_tokens":120}}}}"#,
                #"{"timestamp":"2026-07-10T10:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":70,"output_tokens":35,"total_tokens":195}}}}"#,
                #"{"timestamp":"2026-07-10T10:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":70,"output_tokens":35,"total_tokens":195}}}}"#,
            ].joined(separator: "\n")
            try codexFixture.write(to: codexDirectory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

            let duplicateClaude = #"{"type":"assistant","timestamp":"2026-07-10T11:00:00.000Z","message":{"id":"msg_duplicate","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":30,"cache_creation_input_tokens":20}}}"#
            try [duplicateClaude, duplicateClaude].joined(separator: "\n")
                .write(to: claudeDirectory.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let day = ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z")!
            let codexSummary = AIUsageScanner.scanCodex(root: fixture.appendingPathComponent(".codex"), on: day, calendar: calendar)
            let claudeSummary = AIUsageScanner.scanClaude(root: fixture.appendingPathComponent(".claude"), on: day, calendar: calendar)
            test.check(codexSummary.totalTokens == 195, "Codex cumulative records are not double-counted")
            test.check(codexSummary.sessions == 1, "Codex daily session count")
            test.check(claudeSummary.totalTokens == 65, "Claude duplicate messages are ignored")
            test.check(claudeSummary.sessions == 1, "Claude daily session count")

            // Incremental scanner: second pass with unchanged files should match
            let scanner = AIUsageScanner(homeDirectory: fixture)
            let first = await scanner.scanToday(now: day)
            let second = await scanner.scanToday(now: day)
            test.check(first.codex.totalTokens == second.codex.totalTokens, "incremental codex stable")
            test.check(first.claude.totalTokens == second.claude.totalTokens, "incremental claude stable")
        } catch {
            test.check(false, "usage fixture scan: \(error)")
        }

        let sampler = SystemMetricsSampler()
        _ = await sampler.sample()
        try? await Task.sleep(for: .milliseconds(50))
        let live = await sampler.sample()
        test.check((0...1).contains(live.cpuUsage), "live CPU is bounded")
        test.check(live.memoryTotalBytes > 0 && live.memoryUsedBytes <= live.memoryTotalBytes, "live memory is sane")
        test.check(live.diskTotalBytes >= live.diskUsedBytes, "live disk is sane")
        test.check(!live.diskVolumeName.isEmpty, "disk volume name present")
        test.check(
            [.noBattery, .onBattery, .charging, .chargedOnAC].contains(live.batteryPowerState),
            "battery power state is valid"
        )

        print("\n\(test.passed) checks passed, \(test.failed) failed")
        exit(test.failed == 0 ? 0 : 1)
    }
}
