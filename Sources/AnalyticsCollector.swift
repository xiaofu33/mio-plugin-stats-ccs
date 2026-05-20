//
//  AnalyticsCollector.swift
//  StatsPlugin
//
//  Queries ~/.cc-switch/cc-switch.db (SQLite) via the system sqlite3 CLI
//  to read daily API token usage and cost data.
//
//  Uses Process + sqlite3 -json to avoid linking libsqlite3 in
//  the bundle plugin.
//

import Foundation
import Combine
import os.log

private let analyticsLogger = Logger(subsystem: "com.codeisland", category: "Analytics")

// MARK: - Free functions (outside @MainActor class)

/// Run a SQL query against cc-switch.db using /usr/bin/sqlite3 -json.
/// Runs Process on a DispatchQueue thread via withCheckedContinuation.
private func runSQLite3JSON(sql: String) async -> [[String: Any]]? {
    let dbPath = "\(NSHomeDirectory())/.cc-switch/cc-switch.db"
    guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [dbPath, "-json", sql]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            do { try process.run(); process.waitUntilExit() } catch {
                continuation.resume(returning: nil)
                return
            }
            guard process.terminationStatus == 0 else {
                continuation.resume(returning: nil)
                return
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                continuation.resume(returning: nil)
                return
            }
            continuation.resume(returning: json)
        }
    }
}

/// Query 14 days of token/cost data from cc-switch.db.
private func queryDailyBuckets(
    from startTs: Int, to endTs: Int, dayStarts: [Date]
) async -> [DayBucket] {
    let result = dayStarts.map { DayBucket(dayStart: $0) }

    // 1. Daily totals
    if let rows = await runSQLite3JSON(sql: """
        SELECT date(datetime(created_at, 'unixepoch', 'localtime')) as d,
               COUNT(*) as cnt,
               COALESCE(SUM(input_tokens), 0) as in_tok,
               COALESCE(SUM(output_tokens), 0) as out_tok,
               COALESCE(SUM(cache_read_tokens), 0) as cache_r,
               COALESCE(SUM(cache_creation_tokens), 0) as cache_c,
               COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0) as cost
        FROM proxy_request_logs
        WHERE app_type='claude'
          AND created_at >= \(startTs)
          AND created_at < \(endTs)
        GROUP BY d ORDER BY d
        """)
    {
        for row in rows {
            guard let dateStr = row["d"] as? String else { continue }
            for b in result {
                let cal = Calendar.current
                let dc = cal.dateComponents([.year, .month, .day], from: b.dayStart)
                let bds = String(format: "%04d-%02d-%02d", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0)
                guard bds == dateStr else { continue }
                b.requestCount = (row["cnt"] as? Int) ?? 0
                b.inputTokens = (row["in_tok"] as? Int) ?? 0
                b.outputTokens = (row["out_tok"] as? Int) ?? 0
                b.cacheReadTokens = (row["cache_r"] as? Int) ?? 0
                b.cacheCreationTokens = (row["cache_c"] as? Int) ?? 0
                if let cn = row["cost"] as? NSNumber { b.totalCostUsd = cn.doubleValue }
                break
            }
        }
    }

    // 2. Per-model breakdown
    if let rows = await runSQLite3JSON(sql: """
        SELECT date(datetime(created_at, 'unixepoch', 'localtime')) as d,
               model, COUNT(*) as cnt,
               COALESCE(SUM(input_tokens), 0) as in_tok,
               COALESCE(SUM(output_tokens), 0) as out_tok,
               COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0) as cost
        FROM proxy_request_logs
        WHERE app_type='claude'
          AND created_at >= \(startTs)
          AND created_at < \(endTs)
        GROUP BY d, model ORDER BY d, cost DESC
        """)
    {
        for row in rows {
            guard let dateStr = row["d"] as? String,
                  let model = row["model"] as? String else { continue }
            for b in result {
                let cal = Calendar.current
                let dc = cal.dateComponents([.year, .month, .day], from: b.dayStart)
                let bds = String(format: "%04d-%02d-%02d", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0)
                guard bds == dateStr else { continue }
                var cv: Double = 0
                if let cn = row["cost"] as? NSNumber { cv = cn.doubleValue }
                b.modelUsage[model] = ModelUsageBreakdown(
                    requestCount: (row["cnt"] as? Int) ?? 0,
                    inputTokens: (row["in_tok"] as? Int) ?? 0,
                    outputTokens: (row["out_tok"] as? Int) ?? 0,
                    totalCostUsd: cv
                )
                break
            }
        }
    }

    return result
}

/// Compute 14 days aligned to Monday week boundaries.
private func computeTwoWeeks(referenceDay: Date) async -> (WeeklyReport, WeeklyReport) {
    let cal = Calendar.current

    // Find the most recent Monday (or today if today is Monday).
    // In gregorian calendar: weekday 1=Sun, 2=Mon, ..., 7=Sat
    let weekday = cal.component(.weekday, from: referenceDay)
    let daysFromMonday = (weekday - 2 + 7) % 7 // subtract this many days to reach Monday
    guard let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: referenceDay) else {
        // Fallback to rolling 7-day window
        let dayStarts: [Date] = (0..<14).map { offset in
            cal.date(byAdding: .day, value: -offset, to: referenceDay) ?? referenceDay
        }.reversed()
        let startTs = Int((dayStarts.first ?? referenceDay).timeIntervalSince1970)
        let endTs = Int((referenceDay.addingTimeInterval(86400)).timeIntervalSince1970)
        let buckets = await queryDailyBuckets(from: startTs, to: endTs, dayStarts: dayStarts)
        let days = buckets.map { $0.finalize() }
        return (
            WeeklyReport.aggregate(Array(days.suffix(7))),
            WeeklyReport.aggregate(Array(days.prefix(7)))
        )
    }

    let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday)!

    // Generate 14 days: last Monday through this Sunday
    let dayStarts: [Date] = (0..<14).map { offset in
        cal.date(byAdding: .day, value: offset, to: lastMonday) ?? thisMonday
    }

    let startTs = Int(dayStarts.first!.timeIntervalSince1970)
    let endTs = Int(cal.date(byAdding: .day, value: 7, to: thisMonday)!.timeIntervalSince1970)

    let buckets = await queryDailyBuckets(from: startTs, to: endTs, dayStarts: dayStarts)
    let days = buckets.map { $0.finalize() }
    return (
        WeeklyReport.aggregate(Array(days.suffix(7))), // this week: thisMonday..thisSunday
        WeeklyReport.aggregate(Array(days.prefix(7)))  // last week: lastMonday..lastSunday
    )
}

// MARK: - CachedAnalytics

private struct CachedAnalytics: Codable, Sendable {
    let thisWeek: WeeklyReport
    let lastWeek: WeeklyReport
}

// MARK: - DayBucket

private final class DayBucket: @unchecked Sendable {
    let dayStart: Date
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheCreationTokens = 0
    var totalCostUsd: Double = 0
    var requestCount = 0
    var modelUsage: [String: ModelUsageBreakdown] = [:]

    init(dayStart: Date) { self.dayStart = dayStart }

    func finalize() -> DailyReport {
        DailyReport(
            date: dayStart, sessionCount: requestCount, turnCount: requestCount,
            focusMinutes: 0, toolCounts: [:], skillCounts: [:], mcpServerCounts: [:],
            linesWritten: 0, primaryProjectName: nil, projectCount: 0,
            peakBurstMinutes: 0, filesEdited: 0, peakHour: nil,
            firstActivity: nil, lastActivity: nil, flowBlockCount: 0,
            longestFlowBlockMinutes: 0, projectTimes: [:],
            inputTokens: inputTokens, outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens, cacheCreationTokens: cacheCreationTokens,
            totalCostUsd: totalCostUsd, modelUsage: modelUsage
        )
    }
}

// MARK: - AnalyticsCollector (main actor)

@MainActor
final class AnalyticsCollector: ObservableObject {
    static let shared = AnalyticsCollector()

    @Published private(set) var yesterdayReport: DailyReport?
    @Published private(set) var thisWeek: WeeklyReport?
    @Published private(set) var lastWeek: WeeklyReport?
    @Published private(set) var isComputing: Bool = false
    @Published private(set) var hasLoadedOnce: Bool = false

    private var midnightTimer: Timer?

    /// Tracks the last calendar day for which we actually queried the DB.
    /// nil on first launch so the initial recompute always runs.
    private var lastComputedDayStart: Date?

    private init() {}

    func start() {
        if let cached = Self.loadCache() {
            self.thisWeek = cached.thisWeek
            self.lastWeek = cached.lastWeek
            self.yesterdayReport = cached.thisWeek.days.last
            self.hasLoadedOnce = true
        }
        Task { await recomputeIfNeeded() }
        scheduleNextMidnight()
    }

    func recomputeIfNeeded() async {
        isComputing = true
        defer { isComputing = false }

        let referenceDay = Self.todayStart()
        // If we already queried the DB for today, skip.
        if let last = lastComputedDayStart,
           Calendar.current.isDate(last, inSameDayAs: referenceDay) {
            hasLoadedOnce = true
            return
        }
        lastComputedDayStart = referenceDay

        let (tw, lw) = await Task.detached(priority: .utility) {
            await computeTwoWeeks(referenceDay: referenceDay)
        }.value
        self.thisWeek = tw
        self.lastWeek = lw
        self.yesterdayReport = tw.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: referenceDay) })
            ?? tw.days.last
        self.hasLoadedOnce = true
        Self.saveCache(CachedAnalytics(thisWeek: tw, lastWeek: lw))
    }

    // MARK: - Persistence

    nonisolated private static func cacheFileURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let dir = appSupport.appendingPathComponent("CodeIsland", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("analytics_cache.json")
    }

    nonisolated private static func loadCache() -> CachedAnalytics? {
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedAnalytics.self, from: data)
    }

    nonisolated private static func saveCache(_ cached: CachedAnalytics) {
        guard let url = cacheFileURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cached) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Scheduling

    private func scheduleNextMidnight() {
        midnightTimer?.invalidate()
        let next = Self.nextLocalMidnight()
        midnightTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.recomputeIfNeeded()
                self?.scheduleNextMidnight()
            }
        }
    }

    // MARK: - Date helpers

    static func todayStart() -> Date { Calendar.current.startOfDay(for: Date()) }

    static func nextLocalMidnight() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
    }
}
