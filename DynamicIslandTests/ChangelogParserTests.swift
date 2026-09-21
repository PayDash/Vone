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

/// The Settings changelog page is only ever as correct as this parser: a
/// heading it misreads shows up as a mangled version number, and a bullet it
/// drops is a change the user is told did not happen.
final class ChangelogParserTests: XCTestCase {
    private let sample = """
    # Changelog

    All notable changes to Vone will be documented in this file.

    ## [Unreleased]

    ### Added
    - **Basket — a floating tray**: shake the pointer mid-drag.
    - An entry with `inline code` and a [link](https://example.com).

    ### Fixed
    - Something fixed (#123)

    ## [2.3.3] - 2026-07-24

    ### Added
    - A shipped change.

    ### Changed

    ### ❤️ Special Thanks
    A massive shoutout to everyone who contributed:
    Hariharan Mudaliar, Jis G Jacob
    """

    func testPreambleIsNotARelease() {
        let releases = ChangelogParser.parse(sample)

        XCTAssertEqual(releases.map(\.version), ["Unreleased", "2.3.3"])
        XCTAssertFalse(releases.contains { $0.version.hasPrefix("All notable") })
    }

    func testVersionAndDateAreSeparated() {
        let release = ChangelogParser.parse(sample).last

        XCTAssertEqual(release?.version, "2.3.3")
        XCTAssertEqual(release?.date, "2026-07-24")
        XCTAssertEqual(release?.isUnreleased, false)
    }

    func testUnreleasedHasNoDate() {
        let release = ChangelogParser.parse(sample).first

        XCTAssertEqual(release?.version, "Unreleased")
        XCTAssertNil(release?.date)
        XCTAssertEqual(release?.isUnreleased, true)
    }

    /// The entry's markdown is the view's to render, so the parser has to hand
    /// it over intact — markers included.
    func testBulletsKeepTheirMarkdown() {
        let added = ChangelogParser.parse(sample).first?.sections.first { $0.title == "Added" }

        XCTAssertEqual(added?.items.count, 2)
        XCTAssertEqual(added?.items.first, "**Basket — a floating tray**: shake the pointer mid-drag.")
        XCTAssertEqual(added?.items.last, "An entry with `inline code` and a [link](https://example.com).")
    }

    /// A heading with nothing under it is a placeholder in the file, not an
    /// empty heading to draw on screen.
    func testEmptySectionsAreDropped() {
        let shipped = ChangelogParser.parse(sample).last

        XCTAssertEqual(shipped?.sections.map(\.title), ["Added", "❤️ Special Thanks"])
    }

    /// The contributors block is written as plain lines, not bullets, and is
    /// still part of what changed in that release.
    func testPlainLinesInsideASectionAreKept() {
        let thanks = ChangelogParser.parse(sample).last?.sections.last { $0.title == "❤️ Special Thanks" }

        XCTAssertEqual(thanks?.items.count, 2)
        XCTAssertEqual(thanks?.items.last, "Hariharan Mudaliar, Jis G Jacob")
    }

    func testHeadingWithoutBracketsStillNamesARelease() {
        let releases = ChangelogParser.parse("## 2.0.0 - 2026-01-01\n\n### Added\n- Something.\n")

        XCTAssertEqual(releases.map(\.version), ["2.0.0"])
        XCTAssertEqual(releases.first?.date, "2026-01-01")
    }

    func testEmptyDocumentYieldsNothing() {
        XCTAssertTrue(ChangelogParser.parse("").isEmpty)
    }

    // MARK: The document the app ships

    /// The page reads the bundled `CHANGELOG.md`, so the file being missing from
    /// the bundle — or reshaped into something the parser no longer follows —
    /// has to fail here rather than show an empty page.
    func testShippedChangelogParses() {
        let releases = ChangelogStore.releases

        XCTAssertFalse(releases.isEmpty, "CHANGELOG.md is missing from the app bundle or no longer parses.")
        XCTAssertEqual(releases.first?.version, "Unreleased")
        XCTAssertEqual(Set(releases.map(\.version)).count, releases.count, "Two releases share a version.")

        for release in releases where !release.isUnreleased {
            XCTAssertNotNil(release.date, "\(release.version) has no date.")
        }
    }
}
