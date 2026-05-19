//
//  StandbyStatsView.swift
//  StatsPlugin
//
//  Ultra-compact view shown on the MioIsland notch bar (standby/closed
//  state) — total tokens + cost at a glance, no interaction required.
//

import SwiftUI

struct StandbyStatsView: View {
    @ObservedObject private var analytics = AnalyticsCollector.shared

    var body: some View {
        if let week = analytics.thisWeek {
            let totalTok = week.totalTokens
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "t.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.5))
                    Text(formatToken(totalTok))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.85))
                }

                HStack(spacing: 3) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.7))
                    Text(formatCost(week.totalCostUsd))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.9))
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func formatToken(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "%.2f¢", cost * 100)
        }
        return "<1¢"
    }
}
