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
import Defaults
import Foundation
import OSLog
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

extension Defaults.Keys {
    static let enableOCR = Key<Bool>("enableOCR", default: true)
    /// Keeps the line structure Vision returns instead of flattening the result
    /// into a single paragraph.
    static let ocrPreservesLineBreaks = Key<Bool>("ocrPreservesLineBreaks", default: true)
    /// Shows the small "text copied" panel once recognition finishes.
    static let ocrShowsConfirmation = Key<Bool>("ocrShowsConfirmation", default: true)
    /// Also opens the recognised text in the default plain-text editor, for when
    /// the result is going to be worked on rather than pasted.
    static let ocrOpensEditor = Key<Bool>("ocrOpensEditor", default: false)
}

/// On-device text recognition. Nothing leaves the machine: every request runs
/// through Vision locally.
final class OCRService: ObservableObject {
    static let shared = OCRService()

    /// True while a recognition pass is running, so the UI can say so.
    @Published private(set) var isRecognizing = false

    private let queue = DispatchQueue(label: "com.ebullioscopic.Atoll.ocr", qos: .userInitiated)
    private var confirmationPanel: NSPanel?
    private var confirmationWork: DispatchWorkItem?

    private static let log = os.Logger(subsystem: "com.ebullioscopic.Atoll", category: "OCR")
    fileprivate static let confirmationSize = CGSize(width: 224, height: 56)
    private static let captureTool = "/usr/sbin/screencapture"
    /// How much of a PDF is read. Recognition runs page by page and a book-length
    /// document would hold the queue for minutes, so the tail is left alone and
    /// the fact is logged rather than silently dropped.
    private static let pdfPageLimit = 50

    private init() {}

    // MARK: Screen capture

    /// Lets the user drag a region, recognises the text inside it, and copies the
    /// result. The selection UI is the system one, so behaviour matches the
    /// shortcut people already know from ⇧⌘4.
    func captureRegionAndRecognize() {
        guard Defaults[.enableOCR] else { return }
        guard FileManager.default.fileExists(atPath: Self.captureTool) else {
            Self.log.error("Cannot capture a region: the capture tool is missing.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vone-ocr-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.captureTool)
        process.arguments = ["-i", "-x", url.path]

        process.terminationHandler = { [weak self] _ in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }  // cancelled

            self.queue.async {
                // `-x` writes nothing when the drag is cancelled, which is the
                // same case as the file check above, just a little later.
                guard let text = self.recognize(fileAt: url), !text.isEmpty else { return }
                DispatchQueue.main.async {
                    self.succeed(with: text)
                }
            }
        }

        do {
            try process.run()
        } catch {
            Self.log.error("Could not start a region capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: File recognition

    /// Recognises text in the first of `urls` that yields any, and copies it.
    /// Used by the Quick Action tile, where the selection is whatever was dropped.
    func recognizeImages(at urls: [URL]) async {
        guard Defaults[.enableOCR] else { return }

        let candidates = urls.filter(Self.isRecognizable)
        guard !candidates.isEmpty else { return }

        await MainActor.run { isRecognizing = true }

        let text: String? = await withCheckedContinuation { continuation in
            queue.async {
                var found: String?
                for url in candidates {
                    if let result = self.recognize(fileAt: url), !result.isEmpty {
                        found = result
                        break
                    }
                }
                continuation.resume(returning: found)
            }
        }

        await MainActor.run { isRecognizing = false }

        guard let text, !text.isEmpty else {
            await MainActor.run { self.showConfirmation(text: nil) }
            feedback()
            return
        }

        await MainActor.run { self.succeed(with: text) }
    }

    /// Recognises encoded image data and hands the text back without touching
    /// the clipboard, the panel or the feedback sound.
    ///
    /// Used by the clipboard indexer: a copied screenshot should become
    /// searchable quietly, not announce that recognition happened.
    func recognizeText(inImageData data: Data) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.recognize(cgImage: image))
            }
        }
    }

    /// Recognises this file if Vision is likely to have something to say about it.
    static func isRecognizable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .pdf) || type.conforms(to: .image)
    }

    // MARK: Recognition

    /// Recognises text in an image or the first pages of a PDF.
    func recognize(fileAt url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            return recognizePDF(at: url)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return recognize(cgImage: image)
    }

    func recognize(cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.log.error("Recognition failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let separator = Defaults[.ocrPreservesLineBreaks] ? "\n" : " "
        let text = lines.joined(separator: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func recognizePDF(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }

        if document.pageCount > Self.pdfPageLimit {
            Self.log.info("Reading the first \(Self.pdfPageLimit) of \(document.pageCount) PDF pages.")
        }

        var pages: [String] = []
        let limit = min(document.pageCount, Self.pdfPageLimit)

        for index in 0..<limit {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            if let text = recognize(cgImage: image) {
                pages.append(text)
            }
        }

        let combined = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    // MARK: Output

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func succeed(with text: String) {
        copyToClipboard(text)
        if Defaults[.ocrOpensEditor] {
            openInEditor(text)
        }
        feedback()
        showConfirmation(text: text)
    }

    /// Hands the text to the default plain-text editor. It is written to a
    /// temporary file first, which is the only thing an editor can usefully be
    /// handed from here; the clipboard is set either way.
    private func openInEditor(_ text: String) {
        let name = "Vone OCR \(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            Self.log.error("Could not write the result for the editor: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func feedback() {
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: Confirmation

    /// A click-through panel, so it confirms the copy without ever getting in the
    /// way of whatever the user does next.
    private func showConfirmation(text: String?) {
        guard Defaults[.ocrShowsConfirmation] else { return }

        let panel = confirmationPanel ?? makeConfirmationPanel()
        confirmationPanel = panel

        panel.contentView = NSHostingView(rootView: OCRConfirmationView(text: text))
        positionConfirmationPanel(panel)
        panel.orderFrontRegardless()
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        confirmationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }
            self.confirmationPanel?.orderOut(nil)
        }
        confirmationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func makeConfirmationPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.confirmationSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private func positionConfirmationPanel(_ panel: NSPanel) {
        let point = NSEvent.mouseLocation
        let size = Self.confirmationSize
        var origin = CGPoint(x: point.x + 14, y: point.y - size.height - 14)

        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        panel.setFrameOrigin(origin)
    }
}

// MARK: - View

private struct OCRConfirmationView: View {
    /// The recognised text, or nil when there was nothing to recognise.
    let text: String?

    private var preview: String {
        guard let text else { return String(localized: "No text found") }
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? text
        return firstLine
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: text == nil ? "text.viewfinder" : "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(text == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))

            VStack(alignment: .leading, spacing: 1) {
                Text(text == nil ? "OCR" : "Text copied")
                    .font(.system(size: 11, weight: .semibold))

                Text(preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(
            width: OCRService.confirmationSize.width,
            height: OCRService.confirmationSize.height
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
#endif
