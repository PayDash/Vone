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

import Defaults
import Foundation

/// One provider for every coding agent tokscale can read, instead of one parser
/// per CLI.
///
/// The per-CLI providers stay (they can show detail tokscale does not, such as
/// subscription plan and cache pricing), but this one answers the question they
/// cannot: how much am I using *across* agents, all time, from a single local
/// index. A new agent tokscale learns about shows up here without a change in
/// Vone — that is the point of the roadmap's "agent coverage" item.
struct TokscaleUsageProvider: UsageProvider {
    let id: ProviderID = .tokscale
    /// Settings override; empty means "find it yourself".
    let explicitPath: String

    /// The window the Session row covers. Matches the per-CLI providers' 5 hour
    /// session window so the cards read the same.
    static let sessionWindowHours = 5

    /// How many model rows the card will draw. Tokscale groups by model across
    /// every agent, which is far more rows than fit a card.
    static let modelRowLimit = 6

    init(explicitPath: String = "") {
        self.explicitPath = explicitPath
    }

    // MARK: - Fetch

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        guard let binary = TokscaleCLI.locate(explicitPath: explicitPath.isEmpty ? nil : explicitPath) else {
            throw UsageError.notConfigured("tokscale not found — install it or set its path in Settings")
        }
        let cli = TokscaleCLI(binary: binary)
        let options = Self.options()

        // The all-time report is the base: the agent and model rows, and the
        // all-time total, all come out of it. Everything else is a window the card
        // may not even be drawing, so it is only fetched when its section is on —
        // a section that is off costs no process, not just no rows.
        async let allTime = cli.report()
        async let weekReport = Self.optional(TokscaleReport.self, cli, ["--json", "--week", "--no-spinner"], when: options.week)
        async let todayReport = Self.optional(TokscaleReport.self, cli, ["--json", "--today", "--no-spinner"], when: options.today)
        async let hourlyReport = Self.optional(TokscaleHourlyReport.self, cli, ["hourly", "--json"], when: options.session)
        async let usageReport = Self.optional([TokscaleUsageEntry].self, cli, ["usage", "--json"], when: options.quotas)
        async let metricsReport = Self.optional(TokscaleTimeMetrics.self, cli, ["time-metrics", "--json"], when: options.activity)

        var breakdown = TokscaleBreakdown()

        let all = try await allTime
        guard !all.allEntries.isEmpty else {
            throw UsageError.notFound("No tokscale session data found")
        }

        breakdown.clients = options.agents ? Self.clients(from: all) : []
        breakdown.models = options.models ? Self.models(from: all) : []
        breakdown.totalTokens = all.totalPromptTokens + all.totalOutputTokens
        breakdown.totalCostUSD = all.totalCost ?? 0
        breakdown.totalMessages = all.totalMessages ?? 0

        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now
        if let week = await weekReport { snapshot.week = Self.totals(from: week) }
        if let today = await todayReport { snapshot.today = Self.totals(from: today) }
        if let hourly = await hourlyReport { snapshot.session = Self.session(from: hourly, now: now) }

        // Quota is best-effort: `tokscale usage` asks each provider's own API and is
        // the slowest, least reliable call here. Losing it costs the gauges, not the
        // token totals. The full list is kept even where the card hides a provider,
        // so Settings can offer the ones that exist.
        if let usage = await usageReport {
            breakdown.quotas = Self.quotas(from: usage)
        }
        if let metrics = await metricsReport {
            breakdown.activity = Self.activity(from: metrics)
        }

        snapshot.tokscale = breakdown
        return snapshot
    }

    /// A report the card may not need. Never throws: a section that fails to load
    /// leaves its rows out rather than taking the whole card down.
    private static func optional<T: Decodable>(
        _ type: T.Type,
        _ cli: TokscaleCLI,
        _ arguments: [String],
        when wanted: Bool
    ) async -> T? {
        guard wanted else { return nil }
        return try? await cli.decode(type, arguments: arguments)
    }

    /// Which sections the user asked for, read once per refresh.
    static func options() -> TokscaleCardOptions {
        TokscaleCardOptions(
            session: Defaults[.tokscaleShowSession],
            today: Defaults[.tokscaleShowToday],
            week: Defaults[.tokscaleShowWeek],
            allTime: Defaults[.tokscaleShowAllTime],
            activity: Defaults[.tokscaleShowActivity],
            quotas: Defaults[.tokscaleShowQuotas],
            agents: Defaults[.tokscaleShowAgents],
            models: Defaults[.tokscaleShowModels],
            hiddenQuotaProviders: Defaults[.tokscaleHiddenQuotaProviders]
        )
    }

    // MARK: - Mapping

    /// All-time rows, one per agent, largest first — the ordering the card shows.
    static func clients(from report: TokscaleReport) -> [TokscaleClientTotals] {
        var byClient: [String: TokscaleClientTotals] = [:]
        for entry in report.allEntries {
            let id = entry.client.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            var row = byClient[id] ?? TokscaleClientTotals(client: id, tokens: 0, messages: 0, costUSD: 0)
            row.tokens += entry.promptTokens + entry.outputTokens
            row.messages += entry.messageCount ?? 0
            row.costUSD += entry.cost ?? 0
            byClient[id] = row
        }
        return byClient.values.sorted {
            $0.tokens == $1.tokens ? $0.client < $1.client : $0.tokens > $1.tokens
        }
    }

    /// The same all-time report regrouped by model, which is the view tokscale has
    /// and no single CLI does: one model is often used from several agents, so the
    /// rows carry the agent that spent the most on each.
    static func models(from report: TokscaleReport, limit: Int = modelRowLimit) -> [TokscaleModelTotals] {
        var byModel: [String: TokscaleModelTotals] = [:]
        var perClient: [String: [String: Int]] = [:]

        for entry in report.allEntries {
            guard let raw = entry.model?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let tokens = entry.promptTokens + entry.outputTokens
            var row = byModel[raw] ?? TokscaleModelTotals(model: raw, tokens: 0, costUSD: 0, busiestClient: nil)
            row.tokens += tokens
            row.costUSD += entry.cost ?? 0
            byModel[raw] = row
            perClient[raw, default: [:]][entry.client, default: 0] += tokens
        }

        for (model, spenders) in perClient {
            let busiest = spenders.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key
            byModel[model]?.busiestClient = busiest
        }

        return byModel.values
            .sorted { $0.tokens == $1.tokens ? $0.model < $1.model : $0.tokens > $1.tokens }
            .prefix(max(0, limit))
            .map { $0 }
    }

    static func totals(from report: TokscaleReport) -> UsageTotals {
        var totals = UsageTotals()
        totals.inputTokens = report.totalPromptTokens
        totals.outputTokens = report.totalOutputTokens
        totals.costUSD = report.totalCost ?? 0
        return totals
    }

    /// Sums the hourly buckets that fall inside the session window.
    ///
    /// Tokscale has no "since the last session started" flag, so the window is the
    /// last `sessionWindowHours` hours of the hourly report. A bucketed figure is
    /// coarser than the per-CLI providers' exact cut-off, which is why the card
    /// labels it the same way they do — a window, not a quota.
    static func session(from report: TokscaleHourlyReport, now: Date) -> UsageTotals {
        let cutoff = now.addingTimeInterval(-Double(sessionWindowHours) * 3600)
        var totals = UsageTotals()
        for entry in report.allEntries {
            guard let date = hourFormatter.date(from: entry.hour), date >= cutoff, date <= now else { continue }
            totals.inputTokens += entry.promptTokens
            totals.outputTokens += entry.output ?? 0
            totals.costUSD += entry.cost ?? 0
        }
        return totals
    }

    static func quotas(from entries: [TokscaleUsageEntry]) -> [TokscaleQuota] {
        var quotas: [TokscaleQuota] = []
        for entry in entries {
            for metric in entry.metrics ?? [] {
                // Prefer what the provider said was used; its remaining figure is the
                // same number from the other end and is only a fallback.
                guard let used = metric.usedPercent ?? metric.remainingPercent.map({ 100 - $0 }) else { continue }
                quotas.append(TokscaleQuota(
                    provider: entry.provider,
                    label: metric.label,
                    usedPercent: max(0, min(100, used)),
                    remainingLabel: metric.remainingLabel,
                    resetsAt: metric.resetsAt.flatMap(parseReset)
                ))
            }
        }
        return quotas
    }

    static func activity(from report: TokscaleTimeMetrics?) -> TokscaleActivity? {
        guard let metrics = report?.metrics else { return nil }
        let activity = TokscaleActivity(
            activeSeconds: (metrics.totalActiveTimeMs ?? 0) / 1000,
            longestSessionSeconds: (metrics.longestContinuousMs ?? 0) / 1000,
            maxConcurrentSessions: metrics.maxConcurrentSessions ?? 0,
            sessionCount: metrics.sessionCount ?? 0
        )
        return activity.isEmpty ? nil : activity
    }

    /// `resets_at` is a date on some providers and a timestamp on others.
    private static func parseReset(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let date = resetDateFormatter.date(from: trimmed) { return date }
        if let date = ISO8601DateFormatter().date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: trimmed)
    }

    /// `yyyy-MM-dd HH:mm` in the machine's own time zone — tokscale buckets hours
    /// in local time, so parsing it any other way shifts the window.
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
