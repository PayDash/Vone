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
import Foundation
import UniformTypeIdentifiers

/// One destination a pile of files can be sent to without being dropped anywhere
/// first.
///
/// The strip is shown in the Basket today; the Shelf is meant to carry the same
/// tiles, so nothing here is Basket-specific.
struct QuickAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// What the tile can act on. A tile is offered only when every file in the
    /// selection conforms to at least one of these, so an image-only tool never
    /// shows up next to a folder it cannot do anything with.
    var accepts: [UTType] = [.item]
    /// Whether the files leave the tray once the action runs (move/delete).
    var consumesItems: Bool = false
    /// Tiles reach AppKit, so the action runs on the main actor. Anything slow
    /// inside one has to step off it itself.
    let perform: @MainActor ([URL]) -> Void
}

/// Built-in tiles. Extensions can contribute more later through the same shape.
final class QuickActionRegistry {
    static let shared = QuickActionRegistry()

    private init() {}

    private(set) lazy var builtIn: [QuickAction] = [
        QuickAction(
            id: "airdrop",
            title: String(localized: "AirDrop"),
            systemImage: "dot.radiowaves.left.and.right"
        ) { urls in
            guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
            service.perform(withItems: urls)
        },

        QuickAction(
            id: "mail",
            title: String(localized: "Mail"),
            systemImage: "envelope"
        ) { urls in
            guard let service = NSSharingService(named: .composeEmail) else { return }
            service.perform(withItems: urls)
        },

        QuickAction(
            id: "messages",
            title: String(localized: "Messages"),
            systemImage: "message"
        ) { urls in
            guard let service = NSSharingService(named: .composeMessage) else { return }
            service.perform(withItems: urls)
        },

        QuickAction(
            id: "localsend",
            title: String(localized: "LocalSend"),
            systemImage: "paperplane"
        ) { urls in
            // LocalSend needs a destination first, so the tile opens the same
            // device picker the Shelf uses rather than guessing.
            LocalSendDevicePickerWindowManager.shared.show(
                onDeviceSelected: { device in
                    LocalSendService.shared.selectedDeviceID = device.id
                    Task { try? await LocalSendService.shared.send(items: urls) }
                },
                onDismiss: {}
            )
        },

        QuickAction(
            id: "ocr",
            title: String(localized: "OCR"),
            systemImage: "text.viewfinder",
            accepts: [.image, .pdf]
        ) { urls in
            Task { await OCRService.shared.recognizeImages(at: urls) }
        },

        QuickAction(
            id: "copy-path",
            title: String(localized: "Copy Path"),
            systemImage: "doc.on.clipboard"
        ) { urls in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        },

        QuickAction(
            id: "reveal",
            title: String(localized: "Reveal"),
            systemImage: "folder"
        ) { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        },

        QuickAction(
            id: "open",
            title: String(localized: "Open"),
            systemImage: "arrow.up.forward.app"
        ) { urls in
            urls.forEach { NSWorkspace.shared.open($0) }
        },

        QuickAction(
            id: "trash",
            title: String(localized: "Trash"),
            systemImage: "trash",
            consumesItems: true
        ) { urls in
            NSWorkspace.shared.recycle(urls) { _, _ in }
        },
    ]

    /// Tiles that make sense for the given selection.
    ///
    /// With nothing selected the whole set comes back, so an empty tray keeps the
    /// strip it will have once something is dropped into it rather than showing an
    /// empty row. The strip disables those tiles until there is something to act
    /// on.
    func actions(for urls: [URL]) -> [QuickAction] {
        guard !urls.isEmpty else { return builtIn }

        return builtIn.filter { action in
            urls.allSatisfy { url in
                action.accepts.contains { actionType in
                    Self.contentType(of: url)?.conforms(to: actionType) ?? false
                }
            }
        }
    }

    /// The file's own type where the file system knows it, falling back to the
    /// extension for a URL that is not on disk (a dragged promise, say).
    private static func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: url.pathExtension)
    }
}

extension Array where Element == TrayDrop.DropItem {
    var fileURLs: [URL] { map(\.storageURL) }
}
#endif
