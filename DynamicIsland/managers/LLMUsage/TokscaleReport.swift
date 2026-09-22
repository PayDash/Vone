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

import Foundation

// MARK: - CLI output shapes
//
// These mirror `tokscale --json` (and its `--week` / `--today` variants), the
// `tokscale hourly --json` report and `tokscale usage --json`. Every field is
// optional except the few the CLI always emits, so a report that grows a field
// or drops one never takes the whole snapshot down with it.

/// One row of `tokscale --json`, grouped by client and model by default.
struct TokscaleEntry: Decodable {
    var client: String
    var model: String?
    var provider: String?
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var reasoning: Int?
    var messageCount: Int?
    var cost: Double?

    /// Prompt tokens as the Usage tab counts them elsewhere: cache reads and
    /// writes are a subset of the prompt, so they are folded back in. Tokscale
    /// reports `input` without them and `cacheRead` / `cacheWrite` beside it.
    var promptTokens: Int { (input ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0) }
    var outputTokens: Int { output ?? 0 }
}

/// Top-level shape of `tokscale --json`, `--week` and `--today`: the same
/// entries plus totals for whichever range was asked for.
struct TokscaleReport: Decodable {
    var entries: [TokscaleEntry]?
    var totalInput: Int?
    var totalOutput: Int?
    var totalCacheRead: Int?
    var totalCacheWrite: Int?
    var totalMessages: Int?
    var totalCost: Double?

    var allEntries: [TokscaleEntry] { entries ?? [] }

    /// All prompt tokens for the range, cache included (see `promptTokens`).
    var totalPromptTokens: Int {
        (totalInput ?? 0) + (totalCacheRead ?? 0) + (totalCacheWrite ?? 0)
    }
    var totalOutputTokens: Int { totalOutput ?? 0 }
}

/// One hour bucket of `tokscale hourly --json`. `hour` is local time,
/// formatted `yyyy-MM-dd HH:mm`.
struct TokscaleHourEntry: Decodable {
    var hour: String
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var messageCount: Int?
    var cost: Double?

    var promptTokens: Int { (input ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0) }
}

struct TokscaleHourlyReport: Decodable {
    var entries: [TokscaleHourEntry]?
    var allEntries: [TokscaleHourEntry] { entries ?? [] }
}

/// One provider block of `tokscale usage --json`.
struct TokscaleUsageEntry: Decodable {
    var provider: String
    var plan: String?
    var email: String?
    var metrics: [TokscaleQuotaMetric]?
}

/// A subscription window inside a `tokscale usage --json` entry. `usedPercent`
/// is what the provider's own API reported; `remainingLabel` is a human string
/// such as `"199/200 left"` and is shown verbatim because only the provider
/// knows what it counts.
struct TokscaleQuotaMetric: Decodable {
    var label: String
    var usedPercent: Double?
    var remainingPercent: Double?
    var remainingLabel: String?
    var resetsAt: String?
}

// MARK: - Snapshot-facing values

/// One agent's all-time totals, as tokscale aggregates them across that agent's
/// own session files.
struct TokscaleClientTotals: Equatable, Identifiable {
    var client: String
    var tokens: Int
    var messages: Int
    var costUSD: Double

    var id: String { client }
    var displayName: String { TokscaleDisplay.name(for: client) }
}

/// One model's totals across every agent that used it.
struct TokscaleModelTotals: Equatable, Identifiable {
    var model: String
    var tokens: Int
    var costUSD: Double
    /// The agent that spent the most on this model, for when the name alone does
    /// not say where the usage came from.
    var busiestClient: String?

    var id: String { model }
}

/// `tokscale time-metrics --json`: the shape of the work rather than its size.
struct TokscaleTimeMetrics: Decodable {
    struct Metrics: Decodable {
        var totalActiveTimeMs: Double?
        var totalWallTimeMs: Double?
        var longestContinuousMs: Double?
        var maxConcurrentSessions: Int?
        var sessionCount: Int?
    }
    var metrics: Metrics?
}

/// What `time-metrics` says, in the units the card draws.
struct TokscaleActivity: Equatable {
    var activeSeconds: Double
    var longestSessionSeconds: Double
    var maxConcurrentSessions: Int
    var sessionCount: Int

    var isEmpty: Bool { activeSeconds <= 0 && sessionCount == 0 }

    /// "694 · 7 at once" — the count and the concurrency peak are one fact about
    /// the same sessions, so they share a row. The peak is left out when there was
    /// only ever one session at a time, since it would just repeat the count.
    var sessionSummary: String {
        guard maxConcurrentSessions > 1 else { return "\(sessionCount)" }
        return "\(sessionCount) · \(maxConcurrentSessions) \(String(localized: "at once"))"
    }

    /// Hours and minutes. Agent time runs into days — `time-metrics` reports
    /// 452,964,324 ms here — and "452964s" is not a length anyone pictures.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return hours < 100 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}

/// A subscription quota window, flattened from `tokscale usage --json`.
struct TokscaleQuota: Equatable, Identifiable {
    var provider: String
    var label: String
    /// 0…100.
    var usedPercent: Double
    var remainingLabel: String?
    var resetsAt: Date?

    var id: String { "\(provider)|\(label)" }
    var fraction: Double { max(0, min(1, usedPercent / 100)) }
    var displayName: String { TokscaleDisplay.name(for: provider) }
}

/// What tokscale adds over the per-CLI providers: one card covering every agent
/// it can read, all-time, plus whatever subscription quota the host CLIs expose.
struct TokscaleBreakdown: Equatable {
    var clients: [TokscaleClientTotals] = []
    var models: [TokscaleModelTotals] = []
    var quotas: [TokscaleQuota] = []
    var activity: TokscaleActivity? = nil
    var totalTokens: Int = 0
    var totalCostUSD: Double = 0
    var totalMessages: Int = 0

    var isEmpty: Bool { clients.isEmpty && quotas.isEmpty && totalTokens == 0 }
}

/// Which parts of the tokscale card the user asked for.
///
/// Read once per refresh by the provider, so the answer decides both what is
/// drawn and what is fetched: a section that is off costs no process.
struct TokscaleCardOptions: Equatable {
    var session: Bool
    var today: Bool
    var week: Bool
    var allTime: Bool
    var activity: Bool
    var quotas: Bool
    var agents: Bool
    var models: Bool
    var hiddenQuotaProviders: [String]

    /// Every section on — what a test or a caller with no preferences gets.
    static let all = TokscaleCardOptions(
        session: true, today: true, week: true, allTime: true,
        activity: true, quotas: true, agents: true, models: true,
        hiddenQuotaProviders: []
    )
}

// MARK: - Display names

/// Turns the CLI ids tokscale reports (`opencode`, `devin-cli`, `cherrystudio`)
/// into the names their own users see. Unknown ids are title-cased rather than
/// dropped, so a client tokscale learns about after this build still reads as a
/// word instead of a slug.
enum TokscaleDisplay {
    private static let names: [String: String] = [
        "9router": "9Router",
        "amp": "Amp",
        "antigravity": "Antigravity",
        "antigravity-cli": "Antigravity CLI",
        "augment": "Augment",
        "cherrystudio": "Cherry Studio",
        "claude": "Claude Code",
        "cline": "Cline",
        "codebuff": "Codebuff",
        "codex": "Codex",
        "commandcode": "Command Code",
        "copilot": "Copilot",
        "crush": "Crush",
        "cursor": "Cursor",
        "devin-cli": "Devin CLI",
        "devin-desktop": "Devin",
        "droid": "Droid",
        "freebuff": "Freebuff",
        "gemini": "Gemini CLI",
        "goose": "Goose",
        "grok": "Grok",
        "hermes": "Hermes",
        "jcode": "JCode",
        "junie": "Junie",
        "kilocode": "Kilo Code",
        "kimi": "Kimi",
        "kiro": "Kiro",
        "lmstudio": "LM Studio",
        "micode": "Micode",
        "mux": "Mux",
        "omp": "OMP",
        "openclaw": "OpenClaw",
        "opencode": "OpenCode",
        "opencodereview": "OpenCode Review",
        "qwen": "Qwen",
        "roocode": "Roo Code",
        "synthetic": "Synthetic",
        "trae": "Trae",
        "warp": "Warp",
        "workbuddy": "WorkBuddy",
        "zcode": "ZCode",
        "zed": "Zed",
    ]

    static func name(for id: String) -> String {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let known = names[key] { return known }

        let words = key
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? id : words.joined(separator: " ")
    }
}
