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
import SwiftUI

/// The `CHANGELOG.md` the build shipped with, newest release first.
///
/// A page of its own rather than a section of About: the document runs to a few
/// hundred entries, and a form section holding all of them would be a scroll
/// inside a scroll. The release the running app is on opens on arrival, so the
/// page answers "what changed in this update" without a click.
struct ChangelogSettingsView: View {
    private let releases = ChangelogStore.releases

    /// Open releases, by version. Kept as a set so the disclosure state
    /// survives the list being rebuilt.
    @State private var expandedVersions: Set<String> = []
    @State private var didSeedExpansion = false

    private var currentVersion: String? { Bundle.main.releaseVersionNumber }

    var body: some View {
        VStack {
            Form {
                if releases.isEmpty {
                    Section {
                        Text("This build did not include its changelog.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(releases) { release in
                            releaseDisclosure(release)
                        }
                    } header: {
                        header
                    } footer: {
                        Text("Shipped with this build. A newer release shows its own entries here once you update.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Changelog")
        .onAppear(perform: seedExpansion)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Version history")

            Spacer(minLength: 8)

            Button("Expand all") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedVersions = Set(releases.map(\.id))
                }
            }
            .buttonStyle(.link)

            Button("Collapse all") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedVersions = []
                }
            }
            .buttonStyle(.link)
        }
        .font(.caption)
    }

    // MARK: Releases

    private func releaseDisclosure(_ release: ChangelogRelease) -> some View {
        DisclosureGroup(isExpanded: binding(for: release)) {
            VStack(alignment: .leading, spacing: 10) {
                if release.sections.isEmpty {
                    // The file carries a few releases whose headings are there
                    // but whose entries are not, so the disclosure would
                    // otherwise open onto nothing.
                    Text("No entries recorded for this release.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(release.sections) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(section.items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)

                                Text(markdown(item))
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } label: {
            releaseLabel(release)
        }
    }

    private func releaseLabel(_ release: ChangelogRelease) -> some View {
        HStack(spacing: 8) {
            Text(release.isUnreleased ? String(localized: "Unreleased") : release.version)
                .font(.body.weight(.medium))
                .monospacedDigit()

            if let date = release.date {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if release.version == currentVersion {
                Text("This version")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func binding(for release: ChangelogRelease) -> Binding<Bool> {
        Binding(
            get: { expandedVersions.contains(release.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedVersions.insert(release.id)
                } else {
                    expandedVersions.remove(release.id)
                }
            }
        )
    }

    // MARK: State

    /// Opens the release the running build is on, so the first thing on screen
    /// is what this version changed. Falls back to the newest shipped release
    /// when the build does not match any entry — an unreleased local build, say.
    private func seedExpansion() {
        guard !didSeedExpansion else { return }
        didSeedExpansion = true

        if let currentVersion, releases.contains(where: { $0.version == currentVersion }) {
            expandedVersions = [currentVersion]
        } else if let newest = releases.first(where: { !$0.isUnreleased }) ?? releases.first {
            expandedVersions = [newest.id]
        }
    }

    // MARK: Rendering

    /// The entries are markdown — bullets carry `**bold**` and `` `code` `` —
    /// so they are rendered rather than shown with their markers. Inline-only
    /// syntax keeps a stray `#` inside an entry from restructuring it into a
    /// heading.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
#endif
