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

/// Row of destinations a file can be sent to. Tapping runs the action on the
/// supplied selection; dropping a file onto a tile runs it on that file instead,
/// so a tile works both for a pile that is already parked and for one passing
/// through mid-drag.
///
/// The row is wider than the panel it lives in, so it scrolls -- see
/// `ScrollableRow` for why it does not use a plain `ScrollView`.
struct QuickActionsStrip: View {
    let items: [TrayDrop.DropItem]
    /// Called with the items a consuming action (Trash) has taken over.
    var onConsume: (([TrayDrop.DropItem]) -> Void)? = nil
    var showsTitles: Bool = true

    @State private var targetedActionID: String?
    @State private var hoveredActionID: String?

    private var urls: [URL] { items.fileURLs }

    /// Height of the row, including the strip the scrollbar is drawn in.
    private static func rowHeight(showsTitles: Bool) -> CGFloat {
        showsTitles ? 52 : 36
    }

    var body: some View {
        let actions = QuickActionRegistry.shared.actions(for: urls)

        ScrollableRow(spacing: 6) {
            ForEach(actions) { action in
                tile(action)
            }
        }
        .frame(height: Self.rowHeight(showsTitles: showsTitles))
    }

    private func tile(_ action: QuickAction) -> some View {
        let isTargeted = targetedActionID == action.id
        let isHovered = hoveredActionID == action.id
        let isEnabled = !items.isEmpty

        return Button {
            guard isEnabled else { return }
            action.perform(urls)
            if action.consumesItems {
                onConsume?(items)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 14, weight: .medium))

                if showsTitles {
                    Text(action.title)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
            }
            .frame(
                width: showsTitles ? 50 : 30,
                height: showsTitles ? 42 : 28
            )
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill(isTargeted: isTargeted, isHovered: isHovered, isEnabled: isEnabled))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.white.opacity(0.10),
                        lineWidth: isTargeted ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .help(action.title)
        .onHover { hovering in
            hoveredActionID = hovering ? action.id : (hoveredActionID == action.id ? nil : hoveredActionID)
        }
        .onDrop(
            of: [.fileURL, .image, .url, .text],
            isTargeted: Binding(
                get: { targetedActionID == action.id },
                set: { targetedActionID = $0 ? action.id : nil }
            )
        ) { providers in
            Self.perform(action, providers: providers)
        }
    }

    private func fill(isTargeted: Bool, isHovered: Bool, isEnabled: Bool) -> Color {
        if isTargeted { return Color.accentColor.opacity(0.25) }
        guard isEnabled else { return Color.white.opacity(0.05) }
        return isHovered ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.07)
    }

    /// Dropped files are loaded off the main thread before the action runs, the
    /// same way the Shelf turns providers into items.
    private static func perform(_ action: QuickAction, providers: [NSItemProvider]) -> Bool {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let droppedURLs = providers.interfaceConvert(), !droppedURLs.isEmpty else { return }
            Task { @MainActor in
                action.perform(droppedURLs)
            }
        }
        return true
    }
}
#endif
