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

import XCTest
@testable import Vone

/// The tokscale card is only as correct as the mapping from the CLI's JSON to a
/// snapshot. Every input here is the CLI's own output shape: if tokscale renames
/// a field, the decode fails here rather than as a silently empty card.
final class TokscaleUsageProviderTests: XCTestCase {

    // MARK: Fixtures

    /// Verbatim from `tokscale --json` (values trimmed, shape untouched).
    private let reportJSON = """
    {
      "groupBy": "client,model",
      "entries": [
        {
          "client": "opencode",
          "mergedClients": null,
          "model": "deepseek/deepseek-v4-flash",
          "provider": "freebuff, freebuff2api",
          "input": 1103247,
          "output": 185713,
          "cacheRead": 97249408,
          "cacheWrite": 0,
          "reasoning": 140474,
          "messageCount": 527,
          "cost": 1.3058949479999995,
          "performance": { "msPer1KTokens": 108.18, "totalDurationMs": 10675842, "timedTokens": 98678842, "sampleCount": 493, "tokenCoverage": 1.0 }
        },
        {
          "client": "opencode",
          "mergedClients": null,
          "model": "glm-4.6",
          "provider": "zhipuai",
          "input": 100959,
          "output": 6400,
          "cacheRead": 3112320,
          "cacheWrite": 0,
          "reasoning": 5127,
          "messageCount": 72,
          "cost": 0.42829,
          "performance": { "msPer1KTokens": 123.05, "totalDurationMs": 396821, "timedTokens": 3224806, "sampleCount": 71, "tokenCoverage": 1.0 }
        },
        {
          "client": "jcode",
          "mergedClients": null,
          "model": "claude-haiku-4-5",
          "provider": "copilot",
          "input": 156378,
          "output": 6311,
          "cacheRead": 531968,
          "cacheWrite": 0,
          "reasoning": 0,
          "messageCount": 11,
          "cost": 0.24112980000000003,
          "performance": { "msPer1KTokens": null, "totalDurationMs": 0, "timedTokens": 0, "sampleCount": 0, "tokenCoverage": 0.0 }
        }
      ],
      "totalInput": 14600406,
      "totalOutput": 734443,
      "totalCacheRead": 257592620,
      "totalCacheWrite": 0,
      "totalMessages": 2698,
      "totalCost": 0.000066147,
      "processingTimeMs": 183
    }
    """

    /// Verbatim shape of `tokscale hourly --json`.
    private let hourlyJSON = """
    {
      "entries": [
        { "hour": "2026-07-15 23:00", "clients": ["opencode"], "models": ["glm-4.6"], "input": 49920, "output": 2593, "cacheRead": 284056, "cacheWrite": 0, "messageCount": 27, "turnCount": 0, "cost": 0.017357 },
        { "hour": "2026-07-16 01:00", "clients": ["opencode"], "models": ["glm-4.7-flash"], "input": 35020, "output": 487, "cacheRead": 185630, "cacheWrite": 0, "messageCount": 10, "turnCount": 0, "cost": 0.0 }
      ],
      "totalCost": 0.017357,
      "processingTimeMs": 42
    }
    """

    /// Verbatim shape of `tokscale usage --json`.
    private let usageJSON = """
    [
      {
        "provider": "Copilot",
        "plan": "Individual",
        "email": null,
        "metrics": [
          { "label": "Chat", "used_percent": 0.0, "remaining_percent": 100.0, "remaining_label": "0/0 left", "resets_at": "2026-10-01" },
          { "label": "Premium", "used_percent": 0.4000000000000057, "remaining_percent": 99.6, "remaining_label": "199/200 left", "resets_at": "2026-10-01" }
        ]
      },
      {
        "provider": "Claude Code",
        "plan": "Max",
        "email": null,
        "metrics": [
          { "label": "Session", "remaining_percent": 25.0 }
        ]
      }
    ]
    """

    /// The same strategy the CLI applies: reports are camelCase, `usage --json` is
    /// snake_case. Using a plain decoder here would quietly test a shape the app
    /// never sees.
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    func testDecodesReportShape() throws {
        let report = try decode(TokscaleReport.self, reportJSON)

        XCTAssertEqual(report.allEntries.count, 3)
        XCTAssertEqual(report.totalMessages, 2698)
        XCTAssertEqual(report.totalCost ?? 0, 0.000066147, accuracy: 0.0000001)
        XCTAssertEqual(report.allEntries.first?.messageCount, 527)
    }

    func testDecodesHourlyAndUsageShapes() throws {
        XCTAssertEqual(try decode(TokscaleHourlyReport.self, hourlyJSON).allEntries.count, 2)
        let usage = try decode([TokscaleUsageEntry].self, usageJSON)
        XCTAssertEqual(usage.count, 2)
        XCTAssertEqual(usage.first?.metrics?.count, 2)
    }

    /// A report missing a field the CLI stopped emitting must not fail the decode:
    /// the card degrades, it does not error.
    func testMissingOptionalFieldsDecode() throws {
        let minimal = """
        { "entries": [ { "client": "opencode" } ] }
        """
        let report = try decode(TokscaleReport.self, minimal)

        XCTAssertEqual(report.allEntries.count, 1)
        XCTAssertEqual(report.allEntries.first?.promptTokens, 0)
        XCTAssertEqual(report.totalCost, nil)
    }

    // MARK: Totals

    /// Cache reads and writes are prompt tokens: the per-CLI cards count them in
    /// `inputTokens`, so this card has to as well or the two disagree.
    func testTotalsFoldCacheTokensIntoInput() throws {
        let totals = TokscaleUsageProvider.totals(from: try decode(TokscaleReport.self, reportJSON))

        XCTAssertEqual(totals.inputTokens, 14_600_406 + 257_592_620)
        XCTAssertEqual(totals.outputTokens, 734_443)
        XCTAssertEqual(totals.costUSD, 0.000066147, accuracy: 0.0000001)
        XCTAssertFalse(totals.hasUnpricedModel)
    }

    func testEntryPromptTokensIncludeCache() throws {
        let entry = try XCTUnwrap(try decode(TokscaleReport.self, reportJSON).allEntries.first)

        XCTAssertEqual(entry.promptTokens, 1_103_247 + 97_249_408)
        XCTAssertEqual(entry.outputTokens, 185_713)
    }

    // MARK: Per-agent rows

    func testClientsGroupByAgentAndSortByTokens() throws {
        let clients = TokscaleUsageProvider.clients(from: try decode(TokscaleReport.self, reportJSON))

        XCTAssertEqual(clients.map(\.client), ["opencode", "jcode"], "Largest agent first")
        // Two opencode rows (deepseek + glm) are one agent, not two.
        let opencode = try XCTUnwrap(clients.first)
        XCTAssertEqual(opencode.tokens, (1_103_247 + 97_249_408 + 185_713) + (100_959 + 3_112_320 + 6_400))
        XCTAssertEqual(opencode.messages, 527 + 72)
        XCTAssertEqual(opencode.costUSD, 1.3058949479999995 + 0.42829, accuracy: 0.0000001)
    }

    func testClientsSkipBlankIds() throws {
        let json = """
        { "entries": [ { "client": "", "input": 10 }, { "client": "   ", "input": 10 } ] }
        """
        XCTAssertTrue(TokscaleUsageProvider.clients(from: try decode(TokscaleReport.self, json)).isEmpty)
    }

    // MARK: Per-model rows

    /// One model is often used from more than one agent, which is the view no
    /// single CLI can produce: the rows are grouped by model, not by agent.
    func testModelsGroupAcrossAgentsAndSortByTokens() throws {
        let json = twoClientsSameModelJSON

        let models = TokscaleUsageProvider.models(from: try decode(TokscaleReport.self, json))

        XCTAssertEqual(models.map(\.model), ["shared-model", "quiet-model"])
        XCTAssertEqual(models.first?.tokens, 300)
        XCTAssertEqual(models.first?.costUSD ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(models.first?.busiestClient, "opencode", "the agent that spent the most on it")
    }

    func testModelsRespectTheRowLimit() throws {
        let models = TokscaleUsageProvider.models(from: try decode(TokscaleReport.self, twoClientsSameModelJSON), limit: 1)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.model, "shared-model")
    }

    func testModelsSkipRowsWithNoName() throws {
        let json = """
        { "entries": [ { "client": "opencode" }, { "client": "opencode", "model": "  " } ] }
        """

        XCTAssertTrue(TokscaleUsageProvider.models(from: try decode(TokscaleReport.self, json)).isEmpty)
    }

    // MARK: Activity

    func testActivityConvertsMilliseconds() throws {
        let json = """
        { "metrics": { "total_active_time_ms": 452964324, "total_wall_time_ms": 452964324, "longest_continuous_ms": 8437003, "max_concurrent_sessions": 7, "session_count": 694 } }
        """

        let activity = try XCTUnwrap(TokscaleUsageProvider.activity(from: try decode(TokscaleTimeMetrics.self, json)))

        XCTAssertEqual(activity.activeSeconds, 452_964.324, accuracy: 0.01)
        XCTAssertEqual(activity.longestSessionSeconds, 8_437.003, accuracy: 0.01)
        XCTAssertEqual(activity.maxConcurrentSessions, 7)
        XCTAssertEqual(activity.sessionCount, 694)
    }

    func testActivityIsAbsentWhenThereIsNothingToSay() throws {
        XCTAssertNil(TokscaleUsageProvider.activity(from: nil))
        XCTAssertNil(TokscaleUsageProvider.activity(from: try decode(TokscaleTimeMetrics.self, "{}")))

        let empty = """
        { "metrics": { "session_count": 0 } }
        """
        XCTAssertNil(TokscaleUsageProvider.activity(from: try decode(TokscaleTimeMetrics.self, empty)))
    }

    /// Durations are the one place the card formats numbers itself: agent time runs
    /// to days, and "452964s" is not a length anyone pictures.
    func testDurationFormatting() {
        XCTAssertEqual(TokscaleActivity.duration(0), "0m")
        XCTAssertEqual(TokscaleActivity.duration(-5), "0m")
        XCTAssertEqual(TokscaleActivity.duration(59), "0m")
        XCTAssertEqual(TokscaleActivity.duration(60), "1m")
        XCTAssertEqual(TokscaleActivity.duration(8_437), "2h 20m")
        XCTAssertEqual(TokscaleActivity.duration(359_999), "99h 59m")
        XCTAssertEqual(TokscaleActivity.duration(360_000), "100h", "past 100 hours the minutes are noise")
        XCTAssertEqual(TokscaleActivity.duration(452_964), "125h", "what the machine this was written on actually reports")
    }

    func testSessionSummaryHidesAConcurrencyOfOne() {
        let single = TokscaleActivity(activeSeconds: 10, longestSessionSeconds: 5, maxConcurrentSessions: 1, sessionCount: 694)
        let many = TokscaleActivity(activeSeconds: 10, longestSessionSeconds: 5, maxConcurrentSessions: 7, sessionCount: 694)

        XCTAssertEqual(single.sessionSummary, "694")
        XCTAssertTrue(many.sessionSummary.hasPrefix("694"))
    }

    func testAllSectionsOnIsTheDefaultTheCardAssumes() {
        let all = TokscaleCardOptions.all

        XCTAssertTrue(all.session && all.today && all.week && all.allTime)
        XCTAssertTrue(all.activity && all.quotas && all.agents && all.models)
        XCTAssertTrue(all.hiddenQuotaProviders.isEmpty)
    }

    // MARK: Display names

    func testKnownClientIdsUseTheirOwnNames() {
        XCTAssertEqual(TokscaleDisplay.name(for: "opencode"), "OpenCode")
        XCTAssertEqual(TokscaleDisplay.name(for: "claude"), "Claude Code")
        XCTAssertEqual(TokscaleDisplay.name(for: "devin-cli"), "Devin CLI")
        XCTAssertEqual(TokscaleDisplay.name(for: "OpenCode"), "OpenCode", "Ids are case-insensitive")
    }

    /// An agent tokscale learns about after this build still reads as a name
    /// rather than a slug.
    func testUnknownClientIdsAreTitleCased() {
        XCTAssertEqual(TokscaleDisplay.name(for: "some-new-agent"), "Some New Agent")
        XCTAssertEqual(TokscaleDisplay.name(for: "thing_x"), "Thing X")
        XCTAssertEqual(TokscaleDisplay.name(for: ""), "")
    }

    // MARK: Session window

    func testSessionKeepsOnlyHoursInsideTheWindow() throws {
        let now = Date()
        let inWindow = hourString(now.addingTimeInterval(-2 * 3600 as TimeInterval))
        let old = hourString(now.addingTimeInterval(-9 * 3600 as TimeInterval))
        let json = """
        { "entries": [
            { "hour": "\(inWindow)", "input": 100, "output": 50, "cacheRead": 25, "cost": 0.5 },
            { "hour": "\(old)", "input": 900, "output": 900, "cost": 9.0 }
        ] }
        """

        let session = TokscaleUsageProvider.session(from: try decode(TokscaleHourlyReport.self, json), now: now)

        XCTAssertEqual(session.inputTokens, 125, "Cache reads count as prompt tokens")
        XCTAssertEqual(session.outputTokens, 50)
        XCTAssertEqual(session.costUSD, 0.5, accuracy: 0.0001)
    }

    /// The last five hours is a window, not a quota: a bucket that predates the
    /// cut-off is out even though it is the most recent one there is.
    func testSessionExcludesHoursBeforeTheCutoff() throws {
        let now = Date()
        let window = TimeInterval(TokscaleUsageProvider.sessionWindowHours)
        let justInside = hourString(now.addingTimeInterval(-(window - 1) * 3600))
        let justOutside = hourString(now.addingTimeInterval(-(window + 1) * 3600))
        let json = """
        { "entries": [
            { "hour": "\(justInside)", "input": 10 },
            { "hour": "\(justOutside)", "input": 999 }
        ] }
        """

        let session = TokscaleUsageProvider.session(from: try decode(TokscaleHourlyReport.self, json), now: now)

        XCTAssertEqual(session.inputTokens, 10)
    }

    func testSessionIgnoresUnparseableAndFutureHours() throws {
        let now = Date()
        let json = """
        { "entries": [
            { "hour": "not a date", "input": 500 },
            { "hour": "\(hourString(now.addingTimeInterval(3600)))", "input": 500 }
        ] }
        """

        let session = TokscaleUsageProvider.session(from: try decode(TokscaleHourlyReport.self, json), now: now)

        XCTAssertEqual(session.inputTokens, 0)
    }

    // MARK: Quotas

    func testQuotasUseUsedPercentAndFallBackToRemaining() throws {
        let quotas = TokscaleUsageProvider.quotas(from: try decode([TokscaleUsageEntry].self, usageJSON))

        XCTAssertEqual(quotas.count, 3)
        let premium = try XCTUnwrap(quotas.first { $0.label == "Premium" })
        XCTAssertEqual(premium.provider, "Copilot")
        XCTAssertEqual(premium.usedPercent, 0.4, accuracy: 0.0001)
        XCTAssertEqual(premium.remainingLabel, "199/200 left")

        // Only remaining_percent was reported: 25% left is 75% used.
        let claude = try XCTUnwrap(quotas.first { $0.provider == "Claude Code" })
        XCTAssertEqual(claude.usedPercent, 75, accuracy: 0.0001)
    }

    func testQuotaResetDateIsParsed() throws {
        let quotas = TokscaleUsageProvider.quotas(from: try decode([TokscaleUsageEntry].self, usageJSON))
        let premium = try XCTUnwrap(quotas.first { $0.label == "Premium" })

        let components = try XCTUnwrap(premium.resetsAt).mapComponents()
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 1)
    }

    func testQuotaWithoutAnyPercentageIsSkipped() throws {
        let json = """
        [ { "provider": "Amp", "metrics": [ { "label": "Free" } ] } ]
        """
        XCTAssertTrue(TokscaleUsageProvider.quotas(from: try decode([TokscaleUsageEntry].self, json)).isEmpty)
    }

    func testQuotaFractionIsClamped() {
        let high = TokscaleQuota(provider: "Copilot", label: "Premium", usedPercent: 140)
        let low = TokscaleQuota(provider: "Copilot", label: "Chat", usedPercent: -20)

        XCTAssertEqual(high.fraction, 1)
        XCTAssertEqual(low.fraction, 0)
        XCTAssertEqual(high.displayName, "Copilot")
    }

    // MARK: Binary discovery

    /// The Settings override is the escape hatch for an install discovery cannot
    /// find, so it has to win over both discovery and the cached path.
    func testExplicitPathIsUsedWhenExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let binary = directory.appendingPathComponent("tokscale")
        try Data("#!/bin/sh\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let located = try XCTUnwrap(TokscaleCLI.locate(explicitPath: binary.path))

        XCTAssertEqual(
            located.resolvingSymlinksInPath().path,
            binary.resolvingSymlinksInPath().path
        )
    }

    // MARK: Fixtures

    /// Two agents using one model, plus a second model only one of them touched.
    private var twoClientsSameModelJSON: String {
        """
        { "entries": [
            { "client": "opencode", "model": "shared-model", "input": 100, "output": 100, "cost": 1.0 },
            { "client": "jcode", "model": "shared-model", "input": 50, "output": 50, "cost": 0.5 },
            { "client": "opencode", "model": "quiet-model", "input": 10, "output": 0, "cost": 0.1 }
        ] }
        """
    }

    // MARK: Helpers

    /// Hour buckets are local time, `yyyy-MM-dd HH:mm` — the same format the
    /// provider parses, so the fixtures cannot drift from it.
    private func hourString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private extension Date {
    func mapComponents() -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: self)
    }
}
