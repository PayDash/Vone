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
import os

/// Runs the user's own `tokscale` install and decodes its `--json` output.
///
/// Vone does not bundle tokscale and does not talk to it over the network: the
/// CLI reads the same local session files the per-CLI providers read, so the
/// licence stays GPL-compatible and no data leaves the machine (roadmap §2).
/// One provider covering every agent tokscale knows about also means a new
/// agent is supportable without a new parser here.
struct TokscaleCLI {
    let binary: URL

    static let defaultTimeout: TimeInterval = 25
    private static let log = os.Logger(subsystem: "com.ebullioscopic.Atoll.DynamicIsland", category: "TokscaleCLI")

    /// Resolved once per launch: discovery walks a handful of directories and, in
    /// the worst case, spawns a login shell.
    private static let cached: OSAllocatedUnfairLock<URL?> = OSAllocatedUnfairLock(initialState: nil)

    init(binary: URL) {
        self.binary = binary
    }

    // MARK: - Discovery

    /// Where a GUI-launched app cannot look, but a developer's machine keeps its
    /// node and therefore its node CLIs.
    private static var versionManagerDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".nvm/versions/node"),
            home.appendingPathComponent("Library/Application Support/fnm/node-versions"),
            home.appendingPathComponent(".local/share/fnm/node-versions"),
            home.appendingPathComponent(".nodenv/versions"),
        ]
    }

    private static var fixedDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent(".bun/bin"),
            home.appendingPathComponent(".volta/bin"),
            home.appendingPathComponent(".cargo/bin"),
            home.appendingPathComponent("Library/pnpm"),
            home.appendingPathComponent(".local/share/pnpm"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/usr/bin"),
        ]
    }

    /// `tokscale` as a plain executable path, or nil when the machine does not
    /// have it. `explicitPath` is the user's override from Settings.
    static func locate(explicitPath: String? = nil) -> URL? {
        let manager = FileManager.default

        if let explicitPath {
            let trimmed = explicitPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                if manager.isExecutableFile(atPath: url.path) { return url }
                log.info("Tokscale override is not executable: \(trimmed, privacy: .public)")
            }
        }

        if let cached = cached.withLock({ $0 }) { return cached }

        var directories: [URL] = []

        // An app launched from a terminal inherits a rich PATH; one launched from
        // Finder gets /usr/bin:/bin:/usr/sbin:/sbin and nothing else.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        }
        directories += fixedDirectories
        // nvm/fnm keep every installed node version side by side; newest wins.
        for root in versionManagerDirectories {
            let versions = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            directories += versions
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin") }
        }

        var seen = Set<String>()
        for directory in directories {
            let candidate = directory.appendingPathComponent("tokscale")
            guard seen.insert(candidate.path).inserted else { continue }
            if manager.isExecutableFile(atPath: candidate.path) {
                return remember(candidate)
            }
        }

        // Last resort: ask the user's own login shell, which is the only thing that
        // knows about a PATH assembled in .zshrc (asdf, mise, a custom prefix).
        if let fromShell = loginShellLookup() { return remember(fromShell) }

        log.info("tokscale not found; per-agent providers still apply")
        return nil
    }

    private static func remember(_ url: URL) -> URL {
        // Resolve the shim so the child process inherits the directory of the real
        // script's runtime, not just the directory of the symlink.
        let resolved = url.resolvingSymlinksInPath()
        let target = FileManager.default.isExecutableFile(atPath: resolved.path) ? resolved : url
        cached.withLock { $0 = target }
        log.info("tokscale at \(target.path, privacy: .public)")
        return target
    }

    private static func loginShellLookup() -> URL? {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "command -v tokscale"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        // A shell with a chatty rc file prints to stdout; the answer is the last
        // line that names an existing executable.
        let lines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        for line in lines.reversed() where line.hasPrefix("/") {
            if FileManager.default.isExecutableFile(atPath: line) {
                return URL(fileURLWithPath: line)
            }
        }
        return nil
    }

    // MARK: - Running

    /// `--json` output of one report. Subcommands take `--json` alone; the
    /// default report also accepts `--no-spinner`, which keeps a TUI that wants a
    /// terminal from drawing escape codes into the pipe.
    func run(_ arguments: [String], timeout: TimeInterval = Self.defaultTimeout) async throws -> Data {
        let binary = self.binary
        let environment = childEnvironment()
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = binary
                process.arguments = arguments
                process.environment = environment
                process.standardInput = FileHandle.nullDevice

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: TokscaleCLIError.launchFailed(
                        "Could not run \(binary.lastPathComponent): \(error.localizedDescription)"
                    ))
                    return
                }

                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

                // Drain both pipes before waiting: a report with thousands of rows
                // exceeds the pipe buffer, and waiting first would deadlock on a full
                // buffer until the watchdog killed a perfectly healthy process.
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                guard process.terminationStatus == 0 else {
                    let message = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let detail = message.isEmpty ? "exit code \(process.terminationStatus)" : message
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: TokscaleCLIError.timedOut(
                            "tokscale took longer than \(Int(timeout))s"
                        ))
                    } else {
                        continuation.resume(throwing: TokscaleCLIError.launchFailed(detail))
                    }
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    /// Decodes a report, turning a shape we do not recognise into one readable
    /// failure rather than a crash deeper in the view.
    func decode<T: Decodable>(_ type: T.Type, arguments: [String], timeout: TimeInterval = Self.defaultTimeout) async throws -> T {
        let data = try await run(arguments, timeout: timeout)
        do {
            let decoder = JSONDecoder()
            // The CLI mixes conventions: reports are camelCase while `usage --json`
            // is snake_case (`used_percent`, `remaining_label`, `resets_at`).
            // Converting is a no-op for the camelCase keys and the only way those
            // quota fields ever decode.
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            Self.log.error("tokscale \(arguments.joined(separator: " "), privacy: .public) decoded badly: \(String(describing: error), privacy: .public)")
            throw TokscaleCLIError.badOutput("tokscale output was not in the expected format")
        }
    }

    func report(_ extraArguments: [String] = []) async throws -> TokscaleReport {
        try await decode(TokscaleReport.self, arguments: ["--json", "--no-spinner"] + extraArguments)
    }

    func hourlyReport() async throws -> TokscaleHourlyReport {
        // `hourly` does not accept the global `--no-spinner`, so it is left out.
        try await decode(TokscaleHourlyReport.self, arguments: ["hourly", "--json"])
    }

    /// Subscription quotas. This is the slowest call (each provider's own API) and
    /// the one most likely to be unavailable, so the caller treats it as optional.
    func usageReport() async throws -> [TokscaleUsageEntry] {
        try await decode([TokscaleUsageEntry].self, arguments: ["usage", "--json"], timeout: 20)
    }

    /// The child needs the CLI's own directory on PATH: the installed `tokscale`
    /// is a node script behind a shebang, so `env node` has to resolve, and node
    /// lives wherever nvm/fnm/homebrew put it — which is the same place we found
    /// the CLI.
    private func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var parts = [binary.deletingLastPathComponent().path]
        if let existing = environment["PATH"] {
            parts += existing.split(separator: ":").map(String.init)
        }
        for directory in Self.fixedDirectories where !parts.contains(directory.path) {
            parts.append(directory.path)
        }
        var seen = Set<String>()
        environment["PATH"] = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }
}

enum TokscaleCLIError: LocalizedError {
    case launchFailed(String)
    case timedOut(String)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message), .timedOut(let message), .badOutput(let message):
            return message
        }
    }
}
