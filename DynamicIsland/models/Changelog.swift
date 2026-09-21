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

#if os(macOS)
import Foundation

/// One release block of `CHANGELOG.md` — everything from a `##` heading up to
/// the next one.
struct ChangelogRelease: Identifiable, Equatable {
    /// `2.3.3`, or `Unreleased` for the block that has no shipped build.
    let version: String
    /// The day the release shipped, when the entry carries one.
    let date: String?
    /// `### Added`, `### Fixed`, … in the order the file lists them.
    let sections: [ChangelogSection]

    var id: String { version }

    /// Whether this is the `## [Unreleased]` block. Read from the version the
    /// file gives rather than from the missing date: a released entry that
    /// simply forgot its date is still released.
    var isUnreleased: Bool { version.caseInsensitiveCompare("Unreleased") == .orderedSame }

    var itemCount: Int { sections.reduce(0) { $0 + $1.items.count } }
}

struct ChangelogSection: Identifiable, Equatable {
    /// The `###` heading without the hashes. Empty for items that appear before
    /// any heading, which the file has never done but a hand edit could.
    let title: String
    /// Each bullet, with its `- ` marker removed and its markdown left intact —
    /// the view renders it, so bold and inline code survive.
    let items: [String]

    var id: String { title }
}

/// Reads the [Keep a Changelog](https://keepachangelog.com) document the app
/// ships with.
///
/// Only the shape the file actually uses is handled: `##` releases, `###`
/// sections, `- ` bullets, and the plain paragraph lines the contributors'
/// thank-you block is written in. Anything before the first `##` — the title
/// and the note about the format — belongs to the file rather than to a
/// release, so it is dropped.
enum ChangelogParser {
    static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var version: String?
        var date: String?
        var sections: [ChangelogSection] = []
        var sectionTitle: String?
        var items: [String] = []

        func closeSection() {
            if let title = sectionTitle {
                sections.append(ChangelogSection(title: title, items: items))
            }
            sectionTitle = nil
            items = []
        }

        func closeRelease() {
            closeSection()
            if let version {
                // A section with nothing under it — `### Added` followed
                // straight by the next heading, which the file has — would
                // otherwise draw an empty heading.
                releases.append(
                    ChangelogRelease(
                        version: version,
                        date: date,
                        sections: sections.filter { !$0.items.isEmpty }
                    )
                )
            }
            version = nil
            date = nil
            sections = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("## ") {
                closeRelease()
                (version, date) = parseHeading(String(line.dropFirst(3)))
            } else if line.hasPrefix("### ") {
                closeSection()
                sectionTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if version != nil {
                if line.hasPrefix("- ") {
                    items.append(String(line.dropFirst(2)))
                } else if sectionTitle != nil {
                    // A paragraph inside a section, such as the thanks list.
                    items.append(line)
                }
            }
        }
        closeRelease()

        return releases
    }

    /// `[2.3.3] - 2026-07-24` becomes `("2.3.3", "2026-07-24")`, and
    /// `[Unreleased]` becomes `("Unreleased", nil)`. The brackets are optional:
    /// the file always writes them, but a heading edited by hand may not, and
    /// reading one as part of the version number would print `[2.0.0]` beside a
    /// date on screen.
    private static func parseHeading(_ text: String) -> (version: String, date: String?) {
        var name = text
        var date: String?

        if let separator = name.range(of: " - ") {
            date = String(name[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            name = String(name[..<separator.lowerBound])
        }

        var version = name.trimmingCharacters(in: .whitespaces)
        if version.hasPrefix("[") && version.hasSuffix("]"), version.count > 2 {
            version = String(version.dropFirst().dropLast())
        }

        return (version, date)
    }
}

/// The changelog the running build shipped with.
///
/// `CHANGELOG.md` is copied into the app bundle from the repository root, so
/// updating it there is all it takes for the Settings page to show it — there
/// is no second copy to keep in step.
enum ChangelogStore {
    static let releases: [ChangelogRelease] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return ChangelogParser.parse(markdown)
    }()
}
#endif
