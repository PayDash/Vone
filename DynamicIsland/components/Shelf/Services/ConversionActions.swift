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

import AppKit
import Foundation
import UniformTypeIdentifiers

/// The one entry point for "convert this selection", shared by the Shelf's context
/// menu and the Quick Action tile so the two can never offer different things.
///
/// The chooser is an `NSAlert` with a popup, the same shape the Shelf's existing
/// "Convert Image…" dialog uses. It is deliberately a chooser rather than one
/// hidden default: a video's target size and a PDF's compression level are the
/// user's decision, and guessing produces a file nobody asked for.
@MainActor
enum ConversionActions {

    /// One row of the chooser.
    private struct Operation {
        let title: String
        let run: () async throws -> URL

        init(title: String, run: @escaping () async throws -> URL) {
            self.title = title
            self.run = run
        }
    }

    /// Whether anything in the selection can be converted. Used to decide whether
    /// the menu item and the tile are offered at all.
    static func canConvert(_ urls: [URL]) -> Bool {
        let service = ConversionService.shared
        return urls.contains { service.isPDF($0) || service.isVideo($0) || service.isConvertibleDocument($0) }
    }

    static func present(for urls: [URL]) {
        let service = ConversionService.shared
        let pdfs = urls.filter { service.isPDF($0) }
        let videos = urls.filter { service.isVideo($0) }
        let documents = urls.filter { service.isConvertibleDocument($0) }

        var operations: [Operation] = []

        for level in ConversionService.CompressionLevel.allCases where !pdfs.isEmpty {
            let title = "\(String(localized: "Reduce PDF Size")) — \(level.title)"
            operations.append(Operation(title: title, run: {
                try await Self.compress(pdfs, level: level)
            }))
        }

        if !pdfs.isEmpty {
            let title = String(localized: "Extract Text from PDF")
            operations.append(Operation(title: title, run: {
                try await service.makeText(from: pdfs)
            }))
        }

        for format in ConversionService.TextFormat.allCases where !documents.isEmpty {
            let title = "\(String(localized: "Documents to")) \(format.title)"
            operations.append(Operation(title: title, run: {
                try await Self.convert(documents, to: format, service: service)
            }))
        }

        for target in ConversionService.VideoTarget.allCases where !videos.isEmpty {
            let title = "\(String(localized: "Video")) — \(target.title)"
            operations.append(Operation(title: title, run: {
                try await Self.compressVideo(videos, target: target, service: service)
            }))
        }

        guard !operations.isEmpty else { return }
        present(operations)
    }

    // MARK: - Chooser

    private static func present(_ operations: [Operation]) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Convert")
        alert.informativeText = String(localized: "Choose what to produce. The converted file is added to the Shelf.")
        alert.addButton(withTitle: String(localized: "Convert"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .informational

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
        popup.addItems(withTitles: operations.map(\.title))
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = popup.indexOfSelectedItem
        guard operations.indices.contains(index) else { return }
        let operation = operations[index]

        Task { @MainActor in
            do {
                let result = try await operation.run()
                addToShelf(result)
            } catch {
                let failure = NSAlert()
                failure.messageText = String(localized: "Conversion Failed")
                failure.informativeText = error.localizedDescription
                failure.alertStyle = .warning
                failure.addButton(withTitle: String(localized: "OK"))
                failure.runModal()
            }
        }
    }

    // MARK: - Running

    /// Conversions that take several inputs produce one output each, so the Shelf
    /// ends up with the same number of items the user would get from a converter app.
    private static func convert(
        _ urls: [URL],
        to format: ConversionService.TextFormat,
        service: ConversionService
    ) async throws -> URL {
        if format == .pdf {
            // Many documents become one PDF: that is the reason to select several.
            return try await service.makePDF(fromDocuments: urls)
        }
        var first: URL?
        for url in urls {
            let output = try await service.makeDocument(from: url, as: format)
            if first == nil { first = output }
        }
        guard let first else { throw ConversionError.noInput }
        return first
    }

    private static func compress(_ urls: [URL], level: ConversionService.CompressionLevel) async throws -> URL {
        var first: URL?
        for url in urls {
            let output = try await ConversionService.shared.reducePDFSize(at: url, level: level)
            if first == nil { first = output }
        }
        guard let first else { throw ConversionError.noInput }
        return first
    }

    private static func compressVideo(
        _ urls: [URL],
        target: ConversionService.VideoTarget,
        service: ConversionService
    ) async throws -> URL {
        guard let url = urls.first else { throw ConversionError.noInput }
        return try await service.compressVideo(at: url, target: target)
    }

    private static func addToShelf(_ url: URL) {
        guard let bookmark = try? Bookmark(url: url) else {
            // Without a bookmark the item cannot survive the temp store being
            // cleared, so at least show the user where the file is.
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        ShelfStateViewModel.shared.add([
            ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true, cachedPath: url.standardizedFileURL.path)
        ])
    }
}
