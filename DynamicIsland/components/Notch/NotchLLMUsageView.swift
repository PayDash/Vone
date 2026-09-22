/*
 * Vone (DynamicIsland)
 * Copyright (C) 2024-2026 Vone Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

enum AntigravityPool: String, CaseIterable {
    case gemini = "Gemini"
    case claude = "Claude"
}

struct NotchLLMUsageView: View {
    @ObservedObject private var manager = LLMUsageManager.shared
    @State private var antigravityPool: AntigravityPool = .gemini

    // Which parts of the tokscale card to draw. Read from the same keys the
    // provider uses to decide what to fetch, so a hidden section costs nothing.
    @Default(.tokscaleShowSession) private var tokscaleShowSession
    @Default(.tokscaleShowToday) private var tokscaleShowToday
    @Default(.tokscaleShowWeek) private var tokscaleShowWeek
    @Default(.tokscaleShowAllTime) private var tokscaleShowAllTime
    @Default(.tokscaleShowActivity) private var tokscaleShowActivity
    @Default(.tokscaleShowQuotas) private var tokscaleShowQuotas
    @Default(.tokscaleShowAgents) private var tokscaleShowAgents
    @Default(.tokscaleShowModels) private var tokscaleShowModels
    @Default(.tokscaleHiddenQuotaProviders) private var tokscaleHiddenQuotaProviders

    private func isEnabled(_ provider: ProviderID) -> Bool { Defaults[provider.enabledKey] }

    private var enabledProviders: [ProviderID] {
        ProviderID.allCases.filter { isEnabled($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(enabledProviders) { provider in
                card(for: provider)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
        .onAppear { manager.refreshAll() }
    }

    @ViewBuilder
    private func card(for provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(provider.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                // Subscription plan badge (e.g. "Max 5x"). Only set for Claude; nil elsewhere.
                if case .success(let snap) = manager.results[provider] ?? .loading, let plan = snap.plan {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if provider == .antigravity {
                    Picker("", selection: $antigravityPool) {
                        Text("Gemini").tag(AntigravityPool.gemini)
                        Text("Claude").tag(AntigravityPool.claude)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .controlSize(.mini)
                }
            }
            switch manager.results[provider] ?? .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .failure(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .success(let snap):
                if provider == .newAPI {
                    newAPISuccess(snap)
                } else {
                    success(snap, provider: provider)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        // Stretch every card to the height the panel offers so the row stays uniform
        // (the intent behind the former fixed card height) without a hard-coded size
        // that either clips content or leaves blank space.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func success(_ snap: UsageSnapshot, provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if provider == .antigravity {
                antigravitySuccess(snap)
            } else if provider == .tokscale, let breakdown = snap.tokscale {
                tokscaleSuccess(snap, breakdown: breakdown)
            } else if snap.sessionLimit == nil && snap.weekLimit == nil {
                if provider != .cursor {
                    window("Today", snap.today, prominent: true)
                    window("Week", snap.week)
                    window("Session", snap.session)
                }
                Text("quota unavailable").font(.caption2).foregroundStyle(.secondary.opacity(0.7))
            } else {
                if provider == .cursor {
                    if let limit = snap.sessionLimit { quotaGauge("Cursor Models", limit) }
                    if let limit = snap.weekLimit { quotaGauge("Other Models", limit) }
                } else {
                    if let limit = snap.sessionLimit { quotaGauge("Session", limit) }
                    if let limit = snap.weekLimit { quotaGauge("Week", limit) }
                    VStack(alignment: .leading, spacing: 2) {
                        window("Today", snap.today, compact: true)
                        window("Week", snap.week, compact: true)
                    }
                }
            }
        }
    }

    /// Tokscale's card answers what no single CLI can: which agents are being used,
    /// which models, and what it all adds up to. Windows stay in the same order and
    /// units as the per-CLI cards so the row reads consistently; every section
    /// below them is switchable in Settings ▸ Stats, and was also left out of the
    /// fetch when switched off.
    private func tokscaleSuccess(_ snap: UsageSnapshot, breakdown: TokscaleBreakdown) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if tokscaleShowSession { window("Session", snap.session, compact: true) }
                if tokscaleShowToday { window("Today", snap.today, compact: true) }
                if tokscaleShowWeek { window("Week", snap.week, compact: true) }

                if tokscaleShowAllTime {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("All time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text(tokens(breakdown.totalTokens))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text(money(breakdown.totalCostUSD))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .help("All-time estimated API-equivalent cost across every agent tokscale can read, from local session files.")
                    }
                }

                if tokscaleShowActivity, let activity = breakdown.activity {
                    Divider().overlay(.white.opacity(0.1))
                    Text("Activity").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    tokscaleLabeledRow("Active", TokscaleActivity.duration(activity.activeSeconds))
                    tokscaleLabeledRow("Longest run", TokscaleActivity.duration(activity.longestSessionSeconds))
                    tokscaleLabeledRow("Sessions", activity.sessionSummary)
                }

                let quotas = breakdown.quotas.filter { !tokscaleHiddenQuotaProviders.contains($0.provider) }
                if tokscaleShowQuotas, !quotas.isEmpty {
                    Divider().overlay(.white.opacity(0.1))
                    ForEach(quotas) { quota in
                        quotaGauge("\(quota.displayName) · \(quota.label)", UsageLimit(
                            used: quota.usedPercent,
                            limit: 100,
                            resetsAt: quota.resetsAt
                        ))
                    }
                }

                if tokscaleShowModels, !breakdown.models.isEmpty {
                    Divider().overlay(.white.opacity(0.1))
                    Text("Models").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(breakdown.models) { model in
                        tokscaleSpendRow(model.model, tokens: model.tokens, cost: model.costUSD)
                            .help(model.busiestClient.map { "\(model.model) · mostly \(TokscaleDisplay.name(for: $0))" } ?? model.model)
                    }
                }

                if tokscaleShowAgents, !breakdown.clients.isEmpty {
                    Divider().overlay(.white.opacity(0.1))
                    Text("Agents").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(breakdown.clients) { client in
                        tokscaleSpendRow(client.displayName, tokens: client.tokens, cost: client.costUSD)
                            .help("\(client.tokens) tokens across \(client.messages) messages")
                    }
                }
            }
            .padding(.bottom, 2)
        }
        .frame(height: 135)
    }

    private func tokscaleLabeledRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    private func tokscaleSpendRow(_ name: String, tokens tokenCount: Int, cost: Double) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(tokens(tokenCount))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
            Text(money(cost))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }



    private func antigravitySuccess(_ snap: UsageSnapshot) -> some View {
        let isGemini = antigravityPool == .gemini
        let targetPool = isGemini ? "gemini" : "claude"
        
        // Filter models by pool
        let sessionModel = snap.models.first { $0.model == "Session" && $0.pool == targetPool }
        let weeklyModel = snap.models.first { $0.model == "Weekly" && $0.pool == targetPool }
        
        // Helper to create UsageLimit from model
        func limitFromModel(_ model: ModelUsage?) -> UsageLimit? {
            guard let model = model else { return nil }
            let fraction = model.totals.costUSD
            let usedPct = (1 - max(0, min(1, fraction))) * 100
            return UsageLimit(used: usedPct, limit: 100, resetsAt: model.resetsAt)
        }
        
        return VStack(alignment: .leading, spacing: 6) {
            if let limit = limitFromModel(sessionModel) {
                quotaGauge("Session", limit)
            }
            if let limit = limitFromModel(weeklyModel) {
                quotaGauge("Weekly", limit)
            }
            
            // Token counts and estimated cost read from the language server's
            // conversation history (all pools; Antigravity does not split them).
            VStack(alignment: .leading, spacing: 4) {
                window("Today", snap.today, compact: true)
                window("Week", snap.week, compact: true)
            }
        }
    }

    private func newAPISuccess(_ snap: UsageSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snap.newAPIAccounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(account.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if account.errorMessage != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .help(account.errorMessage ?? "New API account has an error")
                            }
                        }

                        if let errorMessage = account.errorMessage,
                           account.balanceQuota == nil {
                            Text(errorMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            quotaRow("Balance", account.balanceQuota, prominent: true)
                            quotaRow("Used", account.usedQuota)
                            quotaRow("Today", account.todayQuota)
                            quotaRow("Week", account.weekQuota)
                            HStack(spacing: 12) {
                                metric("RPM", account.currentRPM)
                                metric("TPM", account.currentTPM)
                                metric("Requests", account.requestCount)
                            }
                            if let errorMessage = account.errorMessage {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        if account.id != snap.newAPIAccounts.last?.id {
                            Rectangle()
                                .fill(.white.opacity(0.1))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(height: 135)
    }

    private func quotaRow(_ label: String, _ value: Int?, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value.map(quota) ?? "-")
                .font(.system(size: prominent ? 15 : 11, weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer()
        }
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map(quota) ?? "-")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func quotaGauge(_ label: String, _ limit: UsageLimit) -> some View {
        let usedPct = Int(limit.used.rounded())
        let leftPct = max(0, 100 - usedPct)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let resets = resetsIn(limit.resetsAt) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(gaugeTint(limit.fraction)).frame(width: max(4, geo.size.width * limit.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(usedPct)% used").font(.caption2).monospacedDigit()
                Spacer()
                Text("\(leftPct)% left").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func gaugeTint(_ fraction: Double) -> Color {
        if fraction > 0.95 { return .red }
        if fraction > 0.9 { return .orange }
        return .accentColor
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 {
            return "resets in \(days)d \(hours % 24)h \(minutes)m"
        }
        return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
    }

    /// `LocalizedStringKey` rather than `String` on purpose: every call site passes a
    /// literal, and a label handed over as a plain `String` is never extracted, which
    /// left these window names untranslated (§2 rule 5).
    private func window(_ label: LocalizedStringKey, _ totals: UsageTotals, prominent: Bool = false, compact: Bool = false) -> some View {
        let displayValue: String
        if totals.isPercentage {
            displayValue = "\(totals.totalTokens)%"
        } else {
            displayValue = tokens(totals.totalTokens)
        }
        
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 56 : 48, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(displayValue)
                .font(.system(size: compact ? 11 : (prominent ? 17 : 13), weight: prominent ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 4)
            if totals.isPercentage {
                // Quota providers store the remaining fraction in costUSD; it is not money.
                let leftPct = Int((max(0, min(1, totals.costUSD)) * 100).rounded())
                Text("\(leftPct)% left")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(costLabel(totals))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .help(costHelp(totals))
            }
        }
    }

    /// Cost is an estimate computed from local token counts against the API price
    /// table — not a subscription bill. When some models used have no entry in the
    /// table we cannot price them: show "\(money)+" when a partial amount is known,
    /// and an explicit "est. n/a" instead of a misleading "$0.00+" when nothing is.
    private func costLabel(_ totals: UsageTotals) -> String {
        guard totals.hasUnpricedModel else { return money(totals.costUSD) }
        return totals.costUSD > 0 ? money(totals.costUSD) + "+" : "est. n/a"
    }

    private func costHelp(_ totals: UsageTotals) -> String {
        if totals.hasUnpricedModel {
            return "Estimated API-equivalent cost from local token counts (not your subscription bill). Some models used do not have usable pricing, so this is partial or unavailable."
        }
        return "Estimated API-equivalent cost from local token counts (cache reads and writes priced at the provider's cache rates), not your subscription bill."
    }

    private func tokens(_ n: Int) -> String {
        switch n {
        // The cross-agent card is the first to reach billions (cache reads add up),
        // and "3925.8M" is not a number anyone reads at a glance.
        case 1_000_000_000...: return String(format: "%.2fB", Double(n) / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    private func quota(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }

    // Locale-aware formatting pinned to USD — amounts come from the USD pricing table, so the currency code stays fixed.
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    private func money(_ v: Double) -> String {
        Self.currencyFormatter.string(from: v as NSNumber) ?? String(format: "$%.2f", v)
    }
}
