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

struct EmojiPickerView: View {
    @ObservedObject private var manager = EmojiPickerManager.shared
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9)

    private var results: [EmojiEntry] {
        let trimmed = manager.query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return EmojiCatalog.search(trimmed)
        }
        return EmojiCatalog.entries(in: manager.selectedCategory)
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField

            HStack(alignment: .top, spacing: 8) {
                if manager.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    categoryRail
                }
                grid
            }
        }
        .padding(10)
        .frame(width: EmojiPickerManager.panelSize.width, height: EmojiPickerManager.panelSize.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search emoji", text: $manager.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)

            if !manager.query.isEmpty {
                Button {
                    manager.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var categoryRail: some View {
        VStack(spacing: 3) {
            ForEach(EmojiCategory.allCases) { category in
                let selected = category == manager.selectedCategory
                Button {
                    manager.selectedCategory = category
                } label: {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help(category.title)
            }
        }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if manager.query.isEmpty, !manager.recents.isEmpty {
                    recentsSection
                }

                if results.isEmpty {
                    Text("No emoji match")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(results) { entry in
                            emojiButton(entry.value, help: entry.name)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(manager.recents, id: \.self) { emoji in
                    emojiButton(emoji, help: "Recent")
                }
            }
        }
    }

    private func emojiButton(_ emoji: String, help: String) -> some View {
        Button {
            manager.select(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 18))
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
#endif
