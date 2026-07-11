import Foundation

public struct UsageDelta: Sendable, Equatable {
    public var inputTokens: UInt64
    public var outputTokens: UInt64
    public var cachedTokens: UInt64
    public var totalTokens: UInt64
    public var timestamp: Date
    public var recordID: String?

    public init(
        inputTokens: UInt64,
        outputTokens: UInt64,
        cachedTokens: UInt64,
        totalTokens: UInt64,
        timestamp: Date,
        recordID: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.totalTokens = totalTokens
        self.timestamp = timestamp
        self.recordID = recordID
    }
}

private struct FileFingerprint: Equatable {
    var modificationDate: Date
    var fileSize: UInt64
}

private struct FileContribution: Equatable {
    var inputTokens: UInt64 = 0
    var outputTokens: UInt64 = 0
    var cachedTokens: UInt64 = 0
    var totalTokens: UInt64 = 0
    var lastActivity: Date?
    var hasDailyRecord: Bool = false
}

private struct IncrementalFileState {
    var fingerprint: FileFingerprint
    var offset: UInt64 = 0
    var contribution = FileContribution()
    var previousCodexRecord: UsageDelta?
    var seenClaudeRecordIDs = Set<String>()
}

public actor AIUsageScanner {
    private let homeDirectory: URL
    private var dayStart: Date?
    private var codexStates: [String: IncrementalFileState] = [:]
    private var claudeStates: [String: IncrementalFileState] = [:]
    private var codexContributions: [String: FileContribution] = [:]
    private var claudeContributions: [String: FileContribution] = [:]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func scanToday(now: Date = Date(), calendar: Calendar = .current) -> AIUsageSnapshot {
        let start = calendar.startOfDay(for: now)
        if dayStart != start {
            dayStart = start
            codexStates.removeAll()
            claudeStates.removeAll()
            codexContributions.removeAll()
            claudeContributions.removeAll()
        }

        return AIUsageSnapshot(
            capturedAt: now,
            codex: refreshCodex(on: now, calendar: calendar),
            claude: refreshClaude(on: now, calendar: calendar)
        )
    }

    public static func scanCodex(root: URL, on day: Date, calendar: Calendar = .current) -> UsageSummary {
        let roots = ["sessions", "archived_sessions"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            return UsageSummary(statusMessage: "No Codex session folder found")
        }
        return scanCodexFiles(
            existing.flatMap { recentJSONLFiles(under: $0, on: day, calendar: calendar) },
            on: day,
            calendar: calendar
        )
    }

    public static func scanClaude(root: URL, on day: Date, calendar: Calendar = .current) -> UsageSummary {
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projects.path) else {
            return UsageSummary(statusMessage: "No Claude project folder found")
        }
        return scan(
            files: recentJSONLFiles(under: projects, on: day, calendar: calendar),
            on: day,
            calendar: calendar,
            parser: parseClaudeLine
        )
    }

    public static func parseCodexLine(_ data: Data) -> UsageDelta? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any],
              let timestamp = date(from: object["timestamp"]) else { return nil }

        let input = uint(usage["input_tokens"])
        let output = uint(usage["output_tokens"])
        let cached = uint(usage["cached_input_tokens"])
        // Codex reports input_tokens INCLUSIVE of cached_input_tokens (unlike
        // Claude, whose cache counts are separate). Normalize so inputTokens
        // always means uncached input and input + output + cached == total.
        return UsageDelta(
            inputTokens: input >= cached ? input - cached : 0,
            outputTokens: output,
            cachedTokens: cached,
            totalTokens: uint(usage["total_tokens"], fallback: input + output),
            timestamp: timestamp
        )
    }

    public static func parseClaudeLine(_ data: Data) -> UsageDelta? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestamp = date(from: object["timestamp"]) else { return nil }

        let input = uint(usage["input_tokens"])
        let output = uint(usage["output_tokens"])
        let cacheRead = uint(usage["cache_read_input_tokens"])
        let cacheCreated = uint(usage["cache_creation_input_tokens"])
        let cached = cacheRead + cacheCreated
        return UsageDelta(
            inputTokens: input,
            outputTokens: output,
            cachedTokens: cached,
            totalTokens: input + output + cached,
            timestamp: timestamp,
            recordID: message["id"] as? String
        )
    }

    private func refreshCodex(on day: Date, calendar: Calendar) -> UsageSummary {
        let roots = ["sessions", "archived_sessions"].map {
            homeDirectory.appendingPathComponent(".codex/\($0)", isDirectory: true)
        }
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            return UsageSummary(statusMessage: "No Codex session folder found")
        }
        let files = existing.flatMap { Self.recentJSONLFiles(under: $0, on: day, calendar: calendar) }
        let livePaths = Set(files.map(\.path))
        for path in codexContributions.keys where !livePaths.contains(path) {
            codexContributions.removeValue(forKey: path)
            codexStates.removeValue(forKey: path)
        }
        for file in files {
            updateCodexFileIfNeeded(file, day: day, calendar: calendar)
        }
        return Self.summary(from: codexContributions, available: true)
    }

    private func refreshClaude(on day: Date, calendar: Calendar) -> UsageSummary {
        let projects = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projects.path) else {
            return UsageSummary(statusMessage: "No Claude project folder found")
        }
        let files = Self.recentJSONLFiles(under: projects, on: day, calendar: calendar)
        let livePaths = Set(files.map(\.path))
        for path in claudeContributions.keys where !livePaths.contains(path) {
            claudeContributions.removeValue(forKey: path)
            claudeStates.removeValue(forKey: path)
        }
        for file in files {
            updateClaudeFileIfNeeded(file, day: day, calendar: calendar)
        }
        return Self.summary(from: claudeContributions, available: true)
    }

    private func updateCodexFileIfNeeded(_ file: URL, day: Date, calendar: Calendar) {
        let path = file.path
        guard let fingerprint = Self.fingerprint(for: file) else { return }
        if codexStates[path]?.fingerprint == fingerprint { return }
        var state = codexStates[path] ?? IncrementalFileState(fingerprint: fingerprint)
        if fingerprint.fileSize < state.offset {
            state = IncrementalFileState(fingerprint: fingerprint)
        }
        guard let lines = Self.consumeNewBytes(from: file, state: &state) else { return }
        state.fingerprint = fingerprint
        Self.applyCodexLines(lines, to: &state, day: day, calendar: calendar)
        codexStates[path] = state
        codexContributions[path] = state.contribution
    }

    private func updateClaudeFileIfNeeded(_ file: URL, day: Date, calendar: Calendar) {
        let path = file.path
        guard let fingerprint = Self.fingerprint(for: file) else { return }
        if claudeStates[path]?.fingerprint == fingerprint { return }
        var state = claudeStates[path] ?? IncrementalFileState(fingerprint: fingerprint)
        if fingerprint.fileSize < state.offset {
            state = IncrementalFileState(fingerprint: fingerprint)
        }
        guard let lines = Self.consumeNewBytes(from: file, state: &state) else { return }
        state.fingerprint = fingerprint
        Self.applyClaudeLines(lines, to: &state, day: day, calendar: calendar)
        claudeStates[path] = state
        claudeContributions[path] = state.contribution
    }

    /// Reads only bytes appended since the last scan. A trailing partial JSONL
    /// record is deliberately left unread until its newline arrives.
    private static func consumeNewBytes(
        from file: URL,
        state: inout IncrementalFileState
    ) -> [Data]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return [] }
            guard let lastNewline = data.lastIndex(of: 0x0A) else { return [] }
            let complete = data[...lastNewline]
            state.offset &+= UInt64(complete.count)
            let bytes = Array(complete)
            var lines: [Data] = []
            for line in bytes.split(separator: UInt8(0x0A), omittingEmptySubsequences: true) {
                lines.append(Data(line))
            }
            return lines
        } catch {
            return nil
        }
    }

    private static func applyCodexLines(
        _ lines: [Data],
        to state: inout IncrementalFileState,
        day: Date,
        calendar: Calendar
    ) {
        for line in lines {
            guard let current = parseCodexLine(line) else { continue }
            let delta = positiveDelta(current: current, previous: state.previousCodexRecord)
            state.previousCodexRecord = current
            guard calendar.isDate(current.timestamp, inSameDayAs: day), delta.totalTokens > 0 else { continue }
            state.contribution.inputTokens &+= delta.inputTokens
            state.contribution.outputTokens &+= delta.outputTokens
            state.contribution.cachedTokens &+= delta.cachedTokens
            state.contribution.totalTokens &+= delta.totalTokens
            state.contribution.lastActivity = max(state.contribution.lastActivity ?? current.timestamp, current.timestamp)
            state.contribution.hasDailyRecord = true
        }
    }

    private static func applyClaudeLines(
        _ lines: [Data],
        to state: inout IncrementalFileState,
        day: Date,
        calendar: Calendar
    ) {
        for line in lines {
            guard let delta = parseClaudeLine(line),
                  calendar.isDate(delta.timestamp, inSameDayAs: day) else { continue }
            if let recordID = delta.recordID, !state.seenClaudeRecordIDs.insert(recordID).inserted { continue }
            state.contribution.inputTokens &+= delta.inputTokens
            state.contribution.outputTokens &+= delta.outputTokens
            state.contribution.cachedTokens &+= delta.cachedTokens
            state.contribution.totalTokens &+= delta.totalTokens
            state.contribution.lastActivity = max(state.contribution.lastActivity ?? delta.timestamp, delta.timestamp)
            state.contribution.hasDailyRecord = true
        }
    }

    private static func fingerprint(for file: URL) -> FileFingerprint? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? NSNumber,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return FileFingerprint(modificationDate: modified, fileSize: size.uint64Value)
    }

    private static func codexContribution(file: URL, day: Date, calendar: Calendar) -> FileContribution {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return FileContribution() }
        var contribution = FileContribution()
        var previous: UsageDelta?
        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let current = parseCodexLine(Data(rawLine)) else { continue }
            let delta = positiveDelta(current: current, previous: previous)
            previous = current
            guard calendar.isDate(current.timestamp, inSameDayAs: day), delta.totalTokens > 0 else { continue }
            contribution.inputTokens &+= delta.inputTokens
            contribution.outputTokens &+= delta.outputTokens
            contribution.cachedTokens &+= delta.cachedTokens
            contribution.totalTokens &+= delta.totalTokens
            contribution.lastActivity = max(contribution.lastActivity ?? current.timestamp, current.timestamp)
            contribution.hasDailyRecord = true
        }
        return contribution
    }

    private static func claudeContribution(file: URL, day: Date, calendar: Calendar) -> FileContribution {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return FileContribution() }
        var contribution = FileContribution()
        var seen = Set<String>()
        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let delta = parseClaudeLine(Data(rawLine)),
                  calendar.isDate(delta.timestamp, inSameDayAs: day) else { continue }
            if let recordID = delta.recordID, !seen.insert(recordID).inserted { continue }
            contribution.inputTokens &+= delta.inputTokens
            contribution.outputTokens &+= delta.outputTokens
            contribution.cachedTokens &+= delta.cachedTokens
            contribution.totalTokens &+= delta.totalTokens
            contribution.lastActivity = max(contribution.lastActivity ?? delta.timestamp, delta.timestamp)
            contribution.hasDailyRecord = true
        }
        return contribution
    }

    private static func summary(from contributions: [String: FileContribution], available: Bool) -> UsageSummary {
        var input: UInt64 = 0
        var output: UInt64 = 0
        var cached: UInt64 = 0
        var total: UInt64 = 0
        var sessions = 0
        var lastActivity: Date?
        for contribution in contributions.values {
            input &+= contribution.inputTokens
            output &+= contribution.outputTokens
            cached &+= contribution.cachedTokens
            total &+= contribution.totalTokens
            if contribution.hasDailyRecord { sessions += 1 }
            if let activity = contribution.lastActivity {
                lastActivity = max(lastActivity ?? activity, activity)
            }
        }
        return UsageSummary(
            inputTokens: input,
            outputTokens: output,
            cachedTokens: cached,
            totalTokens: total,
            sessions: sessions,
            lastActivity: lastActivity,
            isAvailable: available,
            statusMessage: (available && total == 0 && sessions == 0) ? "No activity today" : nil
        )
    }

    public static func scanCodexFiles(
        _ files: [URL],
        on day: Date,
        calendar: Calendar
    ) -> UsageSummary {
        var totals = UsageDelta(
            inputTokens: 0, outputTokens: 0, cachedTokens: 0, totalTokens: 0, timestamp: day
        )
        var sessions = 0
        var lastActivity: Date?

        for file in files {
            let contribution = codexContribution(file: file, day: day, calendar: calendar)
            totals.inputTokens &+= contribution.inputTokens
            totals.outputTokens &+= contribution.outputTokens
            totals.cachedTokens &+= contribution.cachedTokens
            totals.totalTokens &+= contribution.totalTokens
            if contribution.hasDailyRecord { sessions += 1 }
            if let activity = contribution.lastActivity {
                lastActivity = max(lastActivity ?? activity, activity)
            }
        }

        return UsageSummary(
            inputTokens: totals.inputTokens,
            outputTokens: totals.outputTokens,
            cachedTokens: totals.cachedTokens,
            totalTokens: totals.totalTokens,
            sessions: sessions,
            lastActivity: lastActivity,
            isAvailable: true
        )
    }

    public static func positiveDelta(current: UsageDelta, previous: UsageDelta?) -> UsageDelta {
        guard let previous else { return current }
        func difference(_ current: UInt64, _ previous: UInt64) -> UInt64 {
            current >= previous ? current - previous : current
        }
        return UsageDelta(
            inputTokens: difference(current.inputTokens, previous.inputTokens),
            outputTokens: difference(current.outputTokens, previous.outputTokens),
            cachedTokens: difference(current.cachedTokens, previous.cachedTokens),
            totalTokens: difference(current.totalTokens, previous.totalTokens),
            timestamp: current.timestamp
        )
    }

    public static func scan(
        files: [URL],
        on day: Date,
        calendar: Calendar,
        parser: (Data) -> UsageDelta?
    ) -> UsageSummary {
        var input: UInt64 = 0
        var output: UInt64 = 0
        var cached: UInt64 = 0
        var total: UInt64 = 0
        var sessions = 0
        var lastActivity: Date?
        var seenRecordIDs = Set<String>()

        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            var hasDailyRecord = false
            for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard let delta = parser(Data(rawLine)),
                      calendar.isDate(delta.timestamp, inSameDayAs: day) else { continue }
                if let recordID = delta.recordID, !seenRecordIDs.insert(recordID).inserted {
                    continue
                }
                input &+= delta.inputTokens
                output &+= delta.outputTokens
                cached &+= delta.cachedTokens
                total &+= delta.totalTokens
                lastActivity = max(lastActivity ?? delta.timestamp, delta.timestamp)
                hasDailyRecord = true
            }
            if hasDailyRecord { sessions += 1 }
        }

        return UsageSummary(
            inputTokens: input,
            outputTokens: output,
            cachedTokens: cached,
            totalTokens: total,
            sessions: sessions,
            lastActivity: lastActivity,
            isAvailable: true
        )
    }

    public static func recentJSONLFiles(under root: URL, on day: Date, calendar: Calendar) -> [URL] {
        let start = calendar.startOfDay(for: day)
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= start else { continue }
            files.append(url)
        }
        return files
    }

    private static func date(from value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func uint(_ value: Any?, fallback: UInt64 = 0) -> UInt64 {
        if let number = value as? NSNumber { return number.uint64Value }
        if let string = value as? String, let parsed = UInt64(string) { return parsed }
        return fallback
    }

}
