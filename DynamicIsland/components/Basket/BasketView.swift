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
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Body of a floating basket. The panel hosting this view owns the window; the
/// view only reads and mutates the tray it was handed.
struct BasketView: View {
    let basketID: UUID

    @ObservedObject private var manager = BasketManager.shared
    @State private var isTargeted = false

    private var basket: Basket? {
        manager.baskets.first { $0.id == basketID }
    }

    private var items: [TrayDrop.DropItem] {
        basket?.items ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            separator
            content
            footer
        }
        .padding(10)
        .frame(width: BasketManager.panelSize.width, height: BasketManager.panelSize.height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.white.opacity(0.12),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .animation(.easeOut(duration: 0.14), value: isTargeted)
        .onDrop(of: [.fileURL, .image, .url, .text], isTargeted: $isTargeted) { providers in
            manager.add(providers, to: basketID)
            return true
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Basket")
                .font(.system(size: 11, weight: .semibold))

            Spacer(minLength: 0)

            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button {
                manager.close(basketID: basketID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close basket")
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        row(for: item)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)

            Text(isTargeted ? "Drop to hold it here" : "Drag files here")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for item: TrayDrop.DropItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: item.workspacePreviewImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(Self.byteFormatter.string(fromByteCount: Int64(item.size)))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Button {
                manager.remove(item, from: basketID)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from basket")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(contentsOf: item.storageURL) ?? NSItemProvider()
        }
        .help(item.fileName)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Send to Shelf") {
                manager.sendToShelf(basketID: basketID)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .disabled(items.isEmpty)
            .foregroundStyle(items.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))

            Spacer(minLength: 0)

            Button("Clear") {
                manager.clear(basketID: basketID)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .disabled(items.isEmpty)
            .foregroundStyle(items.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()
}

#endif
