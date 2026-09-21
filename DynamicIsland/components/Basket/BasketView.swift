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
    @State private var hoveredItemID: UUID?

    private var basket: Basket? {
        manager.baskets.first { $0.id == basketID }
    }

    private var items: [TrayDrop.DropItem] {
        basket?.items ?? []
    }

    /// 1-based number of this tray, used when more than one is open.
    private var basketNumber: Int {
        (manager.baskets.firstIndex { $0.id == basketID } ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            separator
            content
            QuickActionsStrip(items: items) { consumed in
                consumed.forEach { manager.remove($0, from: basketID) }
            }
            separator
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

            Text(manager.baskets.count > 1 ? "Basket \(basketNumber)" : "Basket")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if manager.baskets.count > 1 {
                switcher
            }

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
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close basket")
        }
    }

    /// Lets one tray hand the active marker to another, which is otherwise only
    /// reachable by clicking the tray you want.
    private var switcher: some View {
        Menu {
            ForEach(Array(manager.baskets.enumerated()), id: \.element.id) { index, basket in
                Button {
                    manager.activate(basketID: basket.id)
                } label: {
                    let title = "Basket \(index + 1) · \(basket.items.count)"
                    if basket.id == manager.activeBasketID {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Switch basket")
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
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        row(for: item)
                    }
                }
                .padding(.trailing, 2)
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
        let isHovered = hoveredItemID == item.id

        return HStack(spacing: 8) {
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
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
            .help("Remove from basket")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.10 : 0.06))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.storageURL) ?? NSItemProvider()
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.storageURL)
        }
        .help(item.fileName)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            BasketFooterButton(
                title: String(localized: "Send to Shelf"),
                isEnabled: !items.isEmpty,
                tint: .accentColor
            ) {
                manager.sendToShelf(basketID: basketID)
            }

            Spacer(minLength: 0)

            BasketFooterButton(
                title: String(localized: "Clear"),
                isEnabled: !items.isEmpty,
                tint: .secondary
            ) {
                manager.clear(basketID: basketID)
            }
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()
}

// MARK: - Footer button

/// A small text button that reads as clickable: the label lightens and a wash
/// appears behind it on hover, and nothing happens at all when it is disabled.
private struct BasketFooterButton: View {
    let title: String
    let isEnabled: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isHovering && isEnabled ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(foregroundStyle)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.tertiary) }
        return AnyShapeStyle(tint)
    }
}

#endif
