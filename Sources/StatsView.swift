//
//  StatsView.swift
//  StatsPlugin
//
//  Newspaper / magazine layout:
//    Masthead  |  Headline + Deck  |  Stat Strip  |
//    Two-column body (narrative + data table)     |
//    Breakdown boxes (Tools / Skills / MCP)       |
//    Rhythm (week) / Highlights (week)            |
//    Editor's Note (optional)
//

import SwiftUI

struct StatsView: View {
    @ObservedObject private var analytics = AnalyticsCollector.shared
    @ObservedObject private var notes = EditorsNoteService.shared
    @State private var mode: Mode = .day
    @State private var didTriggerNote = false

    private static let lime = Color(red: 0xCA / 255.0, green: 0xFF / 255.0, blue: 0x00 / 255.0)
    private static let ink = Color.white

    enum Mode { case day, week }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if !analytics.hasLoadedOnce {
                loadingState
            } else if let week = analytics.thisWeek, week.hasActivity {
                content(week: week, lastWeek: analytics.lastWeek)
                    .onAppear {
                        if didTriggerNote { return }
                        didTriggerNote = true
                        if let yesterday = week.days.last {
                            PersonalRecords.updateIfBroken(day: yesterday)
                            if notes.isEnabled {
                                // Trigger the note for the current mode only.
                                // Switching modes will lazy-trigger the other one.
                                if mode == .day {
                                    notes.loadOrGenerateDay(for: yesterday)
                                } else {
                                    notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
                                }
                            }
                        }
                    }
            } else {
                noDataState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty states

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)
            ProgressView().scaleEffect(0.7)
            Text(L10n.s("state.loading"))
                .font(.system(size: 11))
                .foregroundColor(Self.ink.opacity(0.45))
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private var noDataState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 60)
            Text(L10n.s("state.empty"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.6))
            Text(L10n.s("state.emptyHint"))
                .font(.system(size: 11))
                .foregroundColor(Self.ink.opacity(0.3))
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(week: WeeklyReport, lastWeek: WeeklyReport?) -> some View {
        let yesterday = week.days.last ?? DailyReport.empty(date: Date())
        let isDay = mode == .day

        VStack(alignment: .leading, spacing: 0) {
            // 1. Summary header (Dynamic Island — total token & cost)
            summaryHeader(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.top, 14)

            thickRule.padding(.top, 8)
            thinRule.padding(.top, 2)
            Spacer().frame(height: 22)

            // 2. Headline + deck
            headlineBlock(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.horizontal, 20)
                .padding(.bottom, 22)

            // 3. Stat strip (4-column bordered band)
            statStrip(week: week, yesterday: yesterday, isDay: isDay)
                .padding(.horizontal, 16)
                .padding(.bottom, 22)

            // 4. Two-column body: left narrative, right data sheet
            twoColumnBody(week: week, yesterday: yesterday, isDay: isDay, lastWeek: lastWeek)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            // 5. Week-only rhythm + highlights
            if !isDay {
                sectionRule(L10n.s("section.rhythm"))
                weekRhythm(week: week)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                let highlights = weekHighlightLines(week: week, lastWeek: lastWeek)
                if !highlights.isEmpty {
                    sectionRule(L10n.s("section.highlights"))
                    highlightList(highlights)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }

            // 6. Breakdowns — 3 bordered columns
            let breakdowns = breakdownSections(week: week, yesterday: yesterday, isDay: isDay)
            if !breakdowns.isEmpty {
                sectionRule(L10n.isChinese ? "细分" : "BREAKDOWN")
                breakdownColumns(breakdowns)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }

            // 7. Editor's Note (optional)
            if notes.isEnabled || !notes.consentAsked {
                sectionRule(L10n.s("note.title"))
                editorsNoteBox(for: yesterday)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }

            // Bottom thick rule closure
            thickRule.padding(.top, 8)
            Spacer().frame(height: 16)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: - Summary Header (Dynamic Island)

    @ViewBuilder
    private func summaryHeader(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        let inTok = isDay ? yesterday.inputTokens : week.inputTokens
        let outTok = isDay ? yesterday.outputTokens : week.outputTokens
        let cost = isDay ? yesterday.totalCostUsd : week.totalCostUsd
        let totalTok = inTok + outTok

        VStack(spacing: 6) {
            thickRule

            // Token & cost numbers — the main attraction
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        statValue(Self.formatTokens(totalTok), label: L10n.isChinese ? "总消耗" : "TOKENS")
                        statValue(Self.formatCost(cost), label: "COST")
                    }
                }
                Spacer()
                modeToggle
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            thinRule

            // Subtle branding line
            HStack {
                Text(Self.brandLine(week: week, yesterday: yesterday, isDay: isDay))
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(Self.ink.opacity(0.45))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
        }
    }

    private func statValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Self.ink.opacity(0.95))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Self.ink.opacity(0.4))
        }
    }

    private static func brandLine(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> String {
        let cal = Calendar.current
        let date: String
        if isDay {
            date = L10n.dayDate(yesterday.date).uppercased()
        } else {
            let start = week.days.first?.date ?? yesterday.date
            date = L10n.weekRange(start, yesterday.date).uppercased()
        }
        return "\(L10n.isChinese ? "代码岛" : "CODE ISLAND") · \(date)"
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(L10n.s("mode.day"), active: mode == .day) {
                mode = .day
                lazyTriggerNote()
            }
            modeButton(L10n.s("mode.week"), active: mode == .week) {
                mode = .week
                lazyTriggerNote()
            }
        }
        .padding(2)
        .background(Capsule().fill(Self.ink.opacity(0.05)))
    }

    /// Trigger the editor's note for the current mode if it isn't
    /// already loaded/loading. Called when user switches modes.
    private func lazyTriggerNote() {
        guard notes.isEnabled, let week = analytics.thisWeek,
              let yesterday = week.days.last else { return }
        let scope: EditorsNoteService.Scope = mode == .day ? .day : .week
        let current = notes.state(for: scope)
        switch current {
        case .idle, .error:
            if scope == .day {
                notes.loadOrGenerateDay(for: yesterday)
            } else {
                notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
            }
        default:
            break
        }
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .black : Self.ink.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(active ? Self.lime : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rules

    private var thickRule: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.4))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
    }

    private var thinRule: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.15))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
    }

    /// Small-caps section label with thin rules above and below — used
    /// like a newspaper cross-head.
    @ViewBuilder
    private func sectionRule(_ label: String) -> some View {
        VStack(spacing: 4) {
            thinRule
            HStack {
                Spacer()
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.5)
                    .foregroundColor(Self.ink.opacity(0.45))
                Spacer()
            }
            .padding(.vertical, 4)
            thinRule
        }
    }

    // MARK: - Headline + deck

    private func headlineBlock(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        let (headline, deck) = headlineAndDeck(week: week, yesterday: yesterday, isDay: isDay)
        return VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            Text(deck)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headlineAndDeck(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> (String, String) {
        let hl = headlineText(week: week, yesterday: yesterday, isDay: isDay)

        // Deck = a short "subtitle" paragraph that teases the main numbers
        if isDay {
            let inTok = Self.formatTokens(yesterday.inputTokens)
            let outTok = Self.formatTokens(yesterday.outputTokens)
            let cost = Self.formatCost(yesterday.totalCostUsd)
            let deck: String
            if L10n.isChinese {
                deck = "\(inTok) 输入 / \(outTok) 输出, 总计 \(cost)"
            } else {
                deck = "\(inTok) in / \(outTok) out, \(cost) total"
            }
            return (hl, deck)
        } else {
            let active = week.days.filter(\.hasActivity).count
            let cost = Self.formatCost(week.totalCostUsd)
            let deck: String
            if L10n.isChinese {
                deck = "\(active) 天活跃, 总计 \(cost)"
            } else {
                deck = "\(active) active days, \(cost) total"
            }
            return (hl, deck)
        }
    }

    private func headlineText(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> String {
        if isDay {
            let totalTok = yesterday.inputTokens + yesterday.outputTokens
            let turns = yesterday.turnCount
            let cachePct = totalTok > 0
                ? Int(Double(yesterday.cacheReadTokens) / Double(totalTok + yesterday.cacheReadTokens) * 100)
                : 0
            let models = yesterday.modelUsage.count
            let hasPro = yesterday.modelUsage.keys.contains { $0.contains("pro") || $0.contains("Pro") }

            if totalTok > 1_000_000 { return L10n.s("hl.heavy") }
            if hasPro && totalTok > 200_000 { return L10n.s("hl.premium") }
            if cachePct >= 60 { return L10n.s("hl.cacheEfficient") }
            if models >= 2 { return L10n.s("hl.multiModel") }
            if totalTok > 400_000 && turns >= 200 { return L10n.s("hl.deepDay") }
            if totalTok > 100_000 && turns >= 50 { return L10n.s("hl.steady") }
            if turns > 0 { return L10n.s("hl.fragmented") }
            return L10n.s("hl.quietDay")
        } else {
            let active = week.days.filter(\.hasActivity).count
            let totalTok = week.inputTokens + week.outputTokens
            if totalTok >= 3_000_000 && active >= 5 { return L10n.s("hl.weekProductive") }
            let maxDay = week.days.map(\.turnCount).max() ?? 0
            let concentration = week.turnCount > 0 ? Double(maxDay) / Double(week.turnCount) : 0
            if concentration >= 0.5 { return L10n.s("hl.weekUneven") }
            if active >= 4 { return L10n.s("hl.weekSteady") }
            return L10n.s("hl.weekQuiet")
        }
    }

    // MARK: - Stat strip (4-column bordered band)

    private func statStrip(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        let inTok = isDay ? yesterday.inputTokens : week.inputTokens
        let outTok = isDay ? yesterday.outputTokens : week.outputTokens
        let cacheTok = isDay ? yesterday.cacheReadTokens : week.cacheReadTokens
        let cost = isDay ? yesterday.totalCostUsd : week.totalCostUsd

        return VStack(spacing: 0) {
            thinRule
            HStack(spacing: 0) {
                statCell(label: L10n.isChinese ? "输入" : "INPUT", value: Self.formatTokens(inTok))
                statDivider
                statCell(label: L10n.isChinese ? "输出" : "OUTPUT", value: Self.formatTokens(outTok))
                statDivider
                statCell(label: L10n.isChinese ? "缓存" : "CACHE", value: Self.formatTokens(cacheTok))
                statDivider
                statCell(label: L10n.isChinese ? "花费" : "COST", value: Self.formatCost(cost))
            }
            .padding(.vertical, 14)
            thinRule
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.8)
                .foregroundColor(Self.ink.opacity(0.45))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Self.ink.opacity(0.95))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Self.ink.opacity(0.12))
            .frame(width: 0.5, height: 40)
    }

    // MARK: - Two-column body

    @ViewBuilder
    private func twoColumnBody(week: WeeklyReport, yesterday: DailyReport, isDay: Bool, lastWeek: WeeklyReport?) -> some View {
        HStack(alignment: .top, spacing: 18) {
            // Left: narrative / insight
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.isChinese ? "叙述" : "THE STORY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.8)
                    .foregroundColor(Self.ink.opacity(0.42))
                bodyStyled(bodyText(week: week, yesterday: yesterday, isDay: isDay, lastWeek: lastWeek))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Vertical rule separator
            Rectangle()
                .fill(Self.ink.opacity(0.12))
                .frame(width: 0.5)

            // Right: data sheet (key/value table)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.isChinese ? "数据" : "BY THE NUMBERS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.8)
                    .foregroundColor(Self.ink.opacity(0.42))
                dataSheet(week: week, yesterday: yesterday, isDay: isDay)
            }
            .frame(width: 180, alignment: .leading)
        }
    }

    // MARK: - Data sheet (right column of two-column body)

    @ViewBuilder
    private func dataSheet(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let rows = dataSheetRows(week: week, yesterday: yesterday, isDay: isDay)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.5))
                    Spacer(minLength: 4)
                    Text(row.1)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Self.ink.opacity(0.85))
                }
            }
        }
    }

    private func dataSheetRows(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> [(String, String)] {
        var rows: [(String, String)] = []
        if isDay {
            let totalTok = yesterday.inputTokens + yesterday.outputTokens
            rows.append((L10n.isChinese ? "请求数" : "requests", "\(yesterday.turnCount)"))
            rows.append((L10n.isChinese ? "模型数" : "models", "\(yesterday.modelUsage.count)"))
            rows.append((L10n.isChinese ? "总 Token" : "total tokens", Self.formatTokens(totalTok)))
            if yesterday.cacheReadTokens > 0 {
                let pct = totalTok > 0 ? Int(Double(yesterday.cacheReadTokens) / Double(totalTok + yesterday.cacheReadTokens) * 100) : 0
                rows.append((L10n.isChinese ? "缓存率" : "cache", "\(pct)%"))
            }
            // Top-2 models by cost
            let topModels = yesterday.modelUsage.sorted { $0.value.totalCostUsd > $1.value.totalCostUsd }.prefix(2)
            for (model, usage) in topModels {
                let shortName = Self.shortModelName(model)
                let costStr = Self.formatCost(usage.totalCostUsd)
                rows.append((shortName, costStr))
            }
        } else {
            let active = week.days.filter(\.hasActivity).count
            let totalTok = week.inputTokens + week.outputTokens
            rows.append((L10n.isChinese ? "活跃天数" : "active days", "\(active) / 7"))
            rows.append((L10n.isChinese ? "总请求" : "total requests", "\(week.turnCount)"))
            rows.append((L10n.isChinese ? "总 Token" : "total tokens", Self.formatTokens(totalTok)))
            rows.append((L10n.isChinese ? "总花费" : "total cost", Self.formatCost(week.totalCostUsd)))
            if week.cacheReadTokens > 0 {
                let pct = totalTok > 0 ? Int(Double(week.cacheReadTokens) / Double(totalTok + week.cacheReadTokens) * 100) : 0
                rows.append((L10n.isChinese ? "缓存率" : "cache", "\(pct)%"))
            }
            if week.streak > 0 {
                rows.append((L10n.isChinese ? "连续天数" : "streak", "\(week.streak)"))
            }
        }
        return rows
    }

    private func truncate(_ str: String, _ maxLen: Int) -> String {
        if str.count <= maxLen { return str }
        return String(str.prefix(maxLen)) + "…"
    }

    // MARK: - Body text (used by The Story column)

    private func bodyStyled(_ text: String) -> some View {
        var parts: [(String, Bool)] = []
        var remaining = text
        while let openRange = remaining.range(of: "<hi>") {
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            if !before.isEmpty { parts.append((before, false)) }
            remaining = String(remaining[openRange.upperBound...])
            if let closeRange = remaining.range(of: "</hi>") {
                let highlighted = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                parts.append((highlighted, true))
                remaining = String(remaining[closeRange.upperBound...])
            }
        }
        if !remaining.isEmpty { parts.append((remaining, false)) }

        var result = Text("")
        for (chunk, hi) in parts {
            let t = Text(chunk)
                .font(.system(size: 13, weight: hi ? .semibold : .regular, design: .serif))
                .foregroundColor(hi ? Self.lime : Self.ink.opacity(0.78))
            result = result + t
        }
        return result
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyText(week: WeeklyReport, yesterday: DailyReport, isDay: Bool, lastWeek: WeeklyReport?) -> String {
        if isDay {
            let inTok = Self.formatTokens(yesterday.inputTokens)
            let outTok = Self.formatTokens(yesterday.outputTokens)
            let cost = Self.formatCost(yesterday.totalCostUsd)
            let models = yesterday.modelUsage.keys.map(Self.shortModelName).joined(separator: ", ")
            if !models.isEmpty {
                return L10n.tpl("body.dayTokens", [
                    "in": "<hi>\(inTok)</hi>",
                    "out": "<hi>\(outTok)</hi>",
                    "cost": cost,
                    "models": models
                ])
            }
            let turns = yesterday.turnCount
            return L10n.tpl("body.dayNoProject", [
                "turns": "<hi>\(turns)</hi>",
                "cost": cost
            ])
        } else {
            let active = week.days.filter(\.hasActivity).count
            let totalTok = Self.formatTokens(week.inputTokens + week.outputTokens)
            return L10n.tpl("body.week", [
                "activeDays": "<hi>\(active)</hi>",
                "tokens": totalTok
            ])
        }
    }

    private func smartInsight(yesterday: DailyReport, week: WeeklyReport, lastWeek: WeeklyReport?) -> String? {
        let totalTok = yesterday.inputTokens + yesterday.outputTokens
        if totalTok > 500_000 {
            return L10n.tpl("insight.heavyTokenUsage", ["n": "<hi>\(Self.formatTokens(totalTok))</hi>"])
        }
        if yesterday.totalCostUsd > 0.50 {
            return L10n.s("insight.premiumCost")
        }
        let cachePct = totalTok > 0
            ? Int(Double(yesterday.cacheReadTokens) / Double(totalTok + yesterday.cacheReadTokens) * 100)
            : 0
        if cachePct >= 70 {
            return L10n.s("insight.highCache")
        }
        let multiModel = yesterday.modelUsage.count >= 2
        if multiModel {
            let models = yesterday.modelUsage.keys.map(Self.shortModelName).joined(separator: ", ")
            return L10n.tpl("insight.multiModel", ["models": models])
        }
        if week.streak == 3 || week.streak == 7 || week.streak == 14 {
            return L10n.tpl("insight.streakMilestone", ["n": "<hi>\(week.streak)</hi>"])
        }
        return nil
    }

    // MARK: - Week rhythm

    @ViewBuilder
    private func weekRhythm(week: WeeklyReport) -> some View {
        let values = week.days.map(\.turnCount)
        let maxVal = max(1, values.max() ?? 1)
        let blocks = ["·", "▁", "▂", "▃", "▅", "▇", "█"]

        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 8) {
                    let ratio = Double(day.turnCount) / Double(maxVal)
                    let level: Int = {
                        if day.turnCount == 0 { return 0 }
                        let idx = Int((ratio * Double(blocks.count - 1)).rounded())
                        return max(1, min(blocks.count - 1, idx))
                    }()
                    Text(blocks[level])
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(day.turnCount > 0 ? Self.lime : Self.ink.opacity(0.15))
                    Text(L10n.weekdayShort(for: day.date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.45))
                    Text("\(day.turnCount)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Self.ink.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Highlights

    private func weekHighlightLines(week: WeeklyReport, lastWeek: WeeklyReport?) -> [String] {
        var lines: [String] = []
        if let peak = week.peakDay, peak.turnCount > 0 {
            lines.append(L10n.tpl("highlight.peakDay", [
                "weekday": L10n.weekdayShort(for: peak.date),
                "turns": "\(peak.turnCount)"
            ]))
        }
        if week.totalCostUsd > 0 {
            lines.append(L10n.tpl("highlight.totalCost", ["cost": Self.formatCost(week.totalCostUsd)]))
        }
        let totalTok = week.inputTokens + week.outputTokens
        if totalTok > 1_000_000 {
            lines.append(L10n.tpl("highlight.totalTokens", ["n": Self.formatTokens(totalTok)]))
        }
        if week.cacheReadTokens > 0 {
            let pct = Int(Double(week.cacheReadTokens) / Double(totalTok + week.cacheReadTokens) * 100)
            if pct >= 30 {
                lines.append(L10n.tpl("highlight.cacheRate", ["pct": "\(pct)"]))
            }
        }
        if week.streak >= 3 {
            lines.append(L10n.tpl("highlight.streak", ["n": "\(week.streak)"]))
        }
        if let lw = lastWeek, lw.hasActivity {
            let diff = week.totalCostUsd - lw.totalCostUsd
            let pct = lw.totalCostUsd > 0 ? Int((abs(diff) / lw.totalCostUsd * 100).rounded()) : 0
            if pct >= 10 {
                if diff > 0 {
                    lines.append(L10n.tpl("highlight.vsLastWeek", ["pct": "\(pct)"]))
                } else {
                    lines.append(L10n.tpl("highlight.vsLastWeekDown", ["pct": "\(pct)"]))
                }
            }
        }
        return lines
    }

    private func highlightList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 10) {
                    Text("§")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .foregroundColor(Self.lime.opacity(0.8))
                    Text(line)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(Self.ink.opacity(0.78))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Breakdown columns (Tools / Skills / MCP)

    private struct Breakdown: Sendable {
        let title: String
        let items: [(String, Int)]
    }

    private func breakdownSections(week: WeeklyReport, yesterday: DailyReport, isDay: Bool) -> [Breakdown] {
        let usage = isDay ? yesterday.modelUsage : {
            var merged: [String: ModelUsageBreakdown] = [:]
            for d in week.days {
                for (model, u) in d.modelUsage {
                    let ex = merged[model] ?? .zero
                    merged[model] = ModelUsageBreakdown(
                        requestCount: ex.requestCount + u.requestCount,
                        inputTokens: ex.inputTokens + u.inputTokens,
                        outputTokens: ex.outputTokens + u.outputTokens,
                        totalCostUsd: ex.totalCostUsd + u.totalCostUsd
                    )
                }
            }
            return merged
        }()

        var out: [Breakdown] = []

        // Model cost breakdown
        let costItems = usage
            .sorted { $0.value.totalCostUsd > $1.value.totalCostUsd }
            .prefix(4)
            .map { (Self.shortModelName($0.key), Int($0.value.totalCostUsd * 100_000)) }
        if !costItems.isEmpty {
            out.append(Breakdown(title: L10n.isChinese ? "模型 (成本)" : "MODELS (COST)", items: costItems))
        }

        // Token volume per model
        let tokItems = usage
            .sorted { ($0.value.inputTokens + $0.value.outputTokens) > ($1.value.inputTokens + $1.value.outputTokens) }
            .prefix(4)
            .map { (Self.shortModelName($0.key), $0.value.inputTokens + $0.value.outputTokens) }
        if !tokItems.isEmpty {
            out.append(Breakdown(title: L10n.isChinese ? "Token 用量" : "TOKEN VOLUME", items: tokItems))
        }

        // Request count per model
        let reqItems = usage
            .sorted { $0.value.requestCount > $1.value.requestCount }
            .prefix(4)
            .map { (Self.shortModelName($0.key), $0.value.requestCount) }
        if !reqItems.isEmpty {
            out.append(Breakdown(title: L10n.isChinese ? "请求次数" : "REQUESTS", items: reqItems))
        }

        return out
    }

    @ViewBuilder
    private func breakdownColumns(_ breakdowns: [Breakdown]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(breakdowns.enumerated()), id: \.offset) { i, bd in
                VStack(alignment: .leading, spacing: 6) {
                    Text(bd.title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundColor(Self.ink.opacity(0.42))
                        .padding(.bottom, 4)
                    ForEach(Array(bd.items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 4) {
                            Text(truncate(item.0, 11))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Self.ink.opacity(0.78))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(item.1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Self.ink.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if i < breakdowns.count - 1 {
                    Rectangle()
                        .fill(Self.ink.opacity(0.12))
                        .frame(width: 0.5, height: 140)
                }
            }
        }
    }

    // MARK: - Editor's Note

    @ViewBuilder
    private func editorsNoteBox(for day: DailyReport) -> some View {
        if !notes.isEnabled && !notes.consentAsked {
            optInCard(for: day)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.isChinese ? "编辑寄语" : "FROM THE EDITOR")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.8)
                        .foregroundColor(Self.ink.opacity(0.42))
                    Spacer()
                    if notes.isEnabled {
                        Button {
                            if mode == .day {
                                notes.loadOrGenerateDay(for: day, force: true)
                            } else if let week = analytics.thisWeek {
                                notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek, force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Self.ink.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let scope: EditorsNoteService.Scope = mode == .day ? .day : .week
                switch notes.state(for: scope) {
                case .idle:
                    EmptyView()
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.5)
                        Text(L10n.s("note.loading"))
                            .font(.system(size: 11, design: .serif))
                            .italic()
                            .foregroundColor(Self.ink.opacity(0.4))
                    }
                case .loaded(let note):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(note.summary)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .italic()
                            .foregroundColor(Self.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                        if !note.tips.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(note.tips.enumerated()), id: \.offset) { _, tip in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("§")
                                            .font(.system(size: 12, weight: .bold, design: .serif))
                                            .foregroundColor(Self.lime.opacity(0.75))
                                        Text(tip)
                                            .font(.system(size: 12, design: .serif))
                                            .foregroundColor(Self.ink.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(4)
                                    }
                                }
                            }
                        }
                    }
                case .error:
                    Text(L10n.s("note.error"))
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundColor(Self.ink.opacity(0.3))
                }
            }
        }
    }

    @ViewBuilder
    private func optInCard(for day: DailyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.s("note.consentBody"))
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundColor(Self.ink.opacity(0.55))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    notes.setEnabled(true)
                    if mode == .day {
                        notes.loadOrGenerateDay(for: day)
                    } else if let week = analytics.thisWeek {
                        notes.loadOrGenerateWeek(for: week, lastWeek: analytics.lastWeek)
                    }
                } label: {
                    Text(L10n.s("note.consentEnable"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Self.lime))
                }
                .buttonStyle(.plain)
                Button {
                    notes.setEnabled(false)
                } label: {
                    Text(L10n.s("note.consentCancel"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Self.ink.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    /// Format a token count for display (e.g. 445871 → "436K", 12036224 → "11.5M").
    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let val = Double(count) / 1_000_000
            if val >= 10 { return String(format: "%.0fM", val) }
            return String(format: "%.1fM", val)
        } else if count >= 1_000 {
            let val = Double(count) / 1_000
            if val >= 100 { return String(format: "%.0fK", val) }
            return String(format: "%.1fK", val)
        }
        return "\(count)"
    }

    /// Format a USD cost for display (e.g. 0.472841 → "$0.473").
    private static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1 {
            return String(format: "$%.3f", cost)
        } else if cost < 100 {
            return String(format: "$%.2f", cost)
        }
        return String(format: "$%.1f", cost)
    }

    /// Shorten a model identifier for display.
    /// deepseek-v4-flash → DS V4 Flash, claude-sonnet-4-6-20260217 → Sonnet 4.6
    private static func shortModelName(_ model: String) -> String {
        // Strip known prefixes
        var name = model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "deepseek-", with: "DS ")
            .replacingOccurrences(of: "gpt-", with: "GPT ")
            .replacingOccurrences(of: "gemini-", with: "Gemini ")
            .replacingOccurrences(of: "kimi-", with: "Kimi ")
            .replacingOccurrences(of: "qwen-", with: "Qwen ")
            .replacingOccurrences(of: "doubao-", with: "Doubao ")
            .replacingOccurrences(of: "glm-", with: "GLM ")
            .replacingOccurrences(of: "mistral-", with: "Mistral ")
            .replacingOccurrences(of: "minimax-", with: "MiniMax ")
        // Strip trailing date segments (e.g. -20260217)
        if name.count >= 12,
           let dashIdx = name.lastIndex(of: "-"),
           dashIdx > name.index(name.endIndex, offsetBy: -12) {
            let suffix = String(name[dashIdx...])
            if suffix.count == 9 && suffix.dropFirst().allSatisfy(\.isNumber) {
                name = String(name[..<dashIdx])
            }
        }
        return name
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
