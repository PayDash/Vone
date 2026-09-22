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

import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import PDFKit
import UniformTypeIdentifiers

/// The half of the roadmap's converter work that `ImageProcessingService` does not
/// cover: PDFs, text documents and video. Images (conversion, background removal,
/// PDF creation) stay where they are.
///
/// Everything here is a system framework — PDFKit, CoreText, AppKit's text system
/// and AVFoundation. No bundled converter binary, so the GPLv3 licence and the
/// no-hosted-service rule both hold (roadmap §2 and §8).
@MainActor
final class ConversionService {
    static let shared = ConversionService()

    private init() {}

    // MARK: - Shapes

    /// How hard to squeeze. The level decides the rasterisation DPI and the JPEG
    /// quality; both are lossy, which is why the UI names the trade rather than
    /// hiding it behind a single "Compress" switch.
    enum CompressionLevel: String, CaseIterable, Identifiable {
        case light, balanced, maximum

        var id: String { rawValue }

        var title: String {
            switch self {
            case .light: return String(localized: "Light (best quality)")
            case .balanced: return String(localized: "Balanced")
            case .maximum: return String(localized: "Maximum (smallest file)")
            }
        }

        /// Dots per inch the pages are re-rendered at. 72 dpi is a 1:1 pixel map of
        /// a 72 dpi PDF, so anything below it is visibly soft.
        var dpi: CGFloat {
            switch self {
            case .light: return 150
            case .balanced: return 110
            case .maximum: return 72
            }
        }

        var jpegQuality: Double {
            switch self {
            case .light: return 0.7
            case .balanced: return 0.5
            case .maximum: return 0.3
            }
        }
    }

    /// A text document format the system text system can both read and write.
    enum TextFormat: String, CaseIterable, Identifiable {
        case pdf, plainText, richText, html

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pdf: return String(localized: "PDF Document")
            case .plainText: return String(localized: "Plain Text")
            case .richText: return String(localized: "Rich Text")
            case .html: return String(localized: "HTML")
            }
        }

        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .plainText: return "txt"
            case .richText: return "rtf"
            case .html: return "html"
            }
        }
    }

    /// Video presets, expressed the way a user actually thinks about them: the
    /// size the file has to end up under (an attachment limit, a messenger cap).
    enum VideoTarget: Int64, CaseIterable, Identifiable {
        case tenMegabytes = 10_000_000
        case twentyFiveMegabytes = 25_000_000
        case fiftyMegabytes = 50_000_000
        case twoHundredMegabytes = 200_000_000

        var id: Int64 { rawValue }

        var title: String {
            String(format: String(localized: "Under %@"), Self.formatter.string(fromByteCount: rawValue))
        }

        private static let formatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useMB]
            formatter.includesUnit = true
            return formatter
        }()
    }

    // MARK: - Which conversions apply

    /// Document types the system text system reads. `.docx` and `.doc` go through
    /// AppKit's own readers, so no converter binary is involved.
    static let documentTypes: [UTType] = [
        .plainText, .utf8PlainText, .rtf, .rtfd, .html, .xml,
        .commaSeparatedText, .tabSeparatedText,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "webarchive") ?? .data,
    ]

    func isPDF(_ url: URL) -> Bool { contentType(of: url)?.conforms(to: .pdf) ?? false }

    func isVideo(_ url: URL) -> Bool {
        guard let type = contentType(of: url) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    /// Whether the service can turn this file into a document. Folders and
    /// unsupported binaries are excluded so a tile never appears for them.
    func isConvertibleDocument(_ url: URL) -> Bool {
        guard let type = contentType(of: url) else { return false }
        return Self.documentTypes.contains { type.conforms(to: $0) }
    }

    private func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: url.pathExtension)
    }

    // MARK: - Documents → PDF / text

    /// Renders one or more documents into a single PDF, laid out with CoreText and
    /// paginated to A4.
    func makePDF(fromDocuments urls: [URL]) async throws -> URL {
        guard !urls.isEmpty else { throw ConversionError.noInput }

        let output = try temporaryURL(named: pdfName(for: urls))
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 dpi
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.writeFailed
        }

        let margin: CGFloat = 48
        let textPath = CGPath(rect: mediaBox.insetBy(dx: margin, dy: margin), transform: nil)
        var wroteAPage = false

        for url in urls {
            let attributed = try attributedString(at: url)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var location = 0
            var pages = 0

            repeat {
                context.beginPDFPage(nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    textPath,
                    nil
                )
                CTFrameDraw(frame, context)
                context.endPDFPage()

                let consumed = CTFrameGetVisibleStringRange(frame).length
                // A frame that fits nothing would loop forever; stop instead of
                // spinning on a document the text system cannot lay out.
                guard consumed > 0 else { break }
                location += consumed
                pages += 1
                wroteAPage = true
            } while location < attributed.length && pages < 500
        }

        context.closePDF()

        guard wroteAPage else { throw ConversionError.writeFailed }
        return output
    }

    /// Pulls the text out: a PDF through PDFKit, anything else through the text
    /// system. Multiple inputs are concatenated so a selection yields one file.
    func makeText(from urls: [URL]) async throws -> URL {
        guard !urls.isEmpty else { throw ConversionError.noInput }

        var pieces: [String] = []
        for url in urls {
            if isPDF(url), let document = PDFDocument(url: url) {
                pieces.append(document.string ?? "")
            } else {
                pieces.append(try attributedString(at: url).string)
            }
        }

        let output = try temporaryURL(named: baseName(for: urls) + ".txt")
        let text = pieces.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ConversionError.nothingToConvert }
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// Converts a document to RTF or HTML by round-tripping it through the text
    /// system, which is what produces those formats from a PDF's text as well.
    func makeDocument(from url: URL, as format: TextFormat) async throws -> URL {
        switch format {
        case .pdf:
            return try await makePDF(fromDocuments: [url])
        case .plainText:
            return try await makeText(from: [url])
        case .richText, .html:
            let attributed = try attributedString(at: url)
            let documentType: NSAttributedString.DocumentType = format == .richText ? .rtf : .html
            let output = try temporaryURL(named: "\(url.deletingPathExtension().lastPathComponent).\(format.fileExtension)")
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: documentType]
            )
            try data.write(to: output)
            return output
        }
    }

    /// Reads any supported document (PDF or text document) into an attributed
    /// string, trying the file's own declared type first.
    private func attributedString(at url: URL) throws -> NSAttributedString {
        if isPDF(url), let document = PDFDocument(url: url) {
            // PDFKit has no attributed output; take the plain string so a PDF still
            // converts to a text document.
            return NSAttributedString(string: document.string ?? "")
        }

        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if let type = contentType(of: url), let documentType = Self.documentType(for: type) {
            options[.documentType] = documentType
        }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            // A file whose extension lied still gets a chance as plain text.
            let text = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: text)
        }
    }

    private static func documentType(for type: UTType) -> NSAttributedString.DocumentType? {
        if type.conforms(to: .rtf) && !type.conforms(to: .rtfd) { return .rtf }
        if type.conforms(to: .rtfd) { return .rtfd }
        if type.conforms(to: .html) { return .html }
        if type.conforms(to: .plainText) { return .plain }
        if type.conforms(to: .commaSeparatedText) || type.conforms(to: .tabSeparatedText) { return .plain }
        switch type.identifier {
        case "org.openxmlformats.wordprocessingml.document": return .officeOpenXML
        case "com.microsoft.word.doc": return .docFormat
        case "com.apple.webarchive": return .webArchive
        default: return nil
        }
    }

    // MARK: - Reduce PDF size

    /// Rewrites a PDF with each page re-rendered at `level.dpi` and encoded as
    /// JPEG. That is the mechanism every "compress PDF" tool uses, and it is worth
    /// being honest about what it costs: the pages become images, so text is no
    /// longer selectable and the result is smaller only when the original was not
    /// already optimised.
    ///
    /// The original stays untouched: this writes a new file beside the temporary
    /// store the Shelf already uses.
    func reducePDFSize(at url: URL, level: CompressionLevel) async throws -> URL {
        guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable }

        let output = try temporaryURL(named: "\(url.deletingPathExtension().lastPathComponent)_reduced.pdf")
        guard let consumer = CGDataConsumer(url: output as CFURL) else { throw ConversionError.writeFailed }

        var mediaBox = CGRect(origin: .zero, size: document.page(at: 0)?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842))
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.writeFailed
        }
        let scale = level.dpi / 72.0
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelWidth = Int((bounds.width * scale).rounded())
            let pixelHeight = Int((bounds.height * scale).rounded())
            guard pixelWidth > 0, pixelHeight > 0,
                  let bitmap = CGContext(
                    data: nil,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { continue }

            // White background: JPEG has no alpha, and a transparent page would
            // come out black.
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            bitmap.scaleBy(x: scale, y: scale)
            guard let cgPage = page.pageRef else { continue }
            bitmap.drawPDFPage(cgPage)

            guard let image = bitmap.makeImage(),
                  let jpeg = Self.jpegData(from: image, quality: level.jpegQuality),
                  let provider = CGDataProvider(data: jpeg as CFData),
                  let jpegImage = CGImage(
                    jpegDataProviderSource: provider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                  ) else { continue }

            var pageBox = CGRect(origin: .zero, size: bounds.size)
            guard let pdfPage = CGPDFPageFromCGImage(jpegImage, &pageBox) else { continue }
            context.beginPDFPage([kCGPDFContextMediaBox as String: NSValue(rect: pageBox)] as CFDictionary)
            context.drawPDFPage(pdfPage)
            context.endPDFPage()
        }

        context.closePDF()

        // A "compression" that grew the file is a failed conversion, not a result.
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        let outputSize = (try? FileManager.default.attributesOfItem(atPath: output.path))?[.size] as? Int64 ?? 0
        if originalSize > 0, outputSize >= originalSize {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.noSavings
        }

        return output
    }

    private static func jpegData(from image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Video target size

    /// Re-encodes a video with a hard ceiling on the file size.
    ///
    /// `fileLengthLimit` is the part that makes this "target size" rather than
    /// "quality preset": AVFoundation picks the bitrate to land under the limit, so
    /// the result is the size the user asked for instead of whatever a preset
    /// happens to produce. The ceiling is a budget for video and audio together.
    func compressVideo(at url: URL, target: VideoTarget) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let presets = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPresetMediumQuality]

        var session: AVAssetExportSession?
        for preset in presets {
            if let candidate = AVAssetExportSession(asset: asset, presetName: preset) {
                session = candidate
                break
            }
        }
        guard let export = session else { throw ConversionError.noEncoder }

        let output = try temporaryURL(named: "\(url.deletingPathExtension().lastPathComponent)_\(target.rawValue / 1_000_000)mb.mp4")
        export.outputURL = output
        export.outputFileType = .mp4
        export.fileLengthLimit = target.rawValue
        export.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.exportFailed(export.error?.localizedDescription ?? String(localized: "The video could not be converted"))
        }
        return output
    }

    // MARK: - Output plumbing

    /// Temporary files live in the same store the Shelf's other outputs use, so
    /// the new item behaves like a dropped file (including being cleaned up).
    private func temporaryURL(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoneConversions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Two conversions of the same file must not overwrite each other.
        let unique = "\(UUID().uuidString.prefix(8))-\(name)"
        return directory.appendingPathComponent(unique)
    }

    private func baseName(for urls: [URL]) -> String {
        guard let first = urls.first else { return "converted" }
        let name = first.deletingPathExtension().lastPathComponent
        return urls.count > 1 ? "\(name)_and_\(urls.count - 1)_more" : name
    }

    private func pdfName(for urls: [URL]) -> String { baseName(for: urls) + ".pdf" }
}

/// `CGPDFPage` only comes from a PDF source, so a page rendered to an image is
/// wrapped back into a one-page PDF document and drawn from there. This keeps the
/// re-encoding path inside CoreGraphics rather than shelling out to `sips`.
private func CGPDFPageFromCGImage(_ image: CGImage, _ box: inout CGRect) -> CGPDFPage? {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = box
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
    context.beginPDFPage(nil)
    context.draw(image, in: mediaBox)
    context.endPDFPage()
    context.closePDF()

    guard let provider = CGDataProvider(data: data as CFData),
          let document = CGPDFDocument(provider) else { return nil }
    let page = document.page(at: 1)
    if let page { box = page.getBoxRect(.mediaBox) }
    return page
}

enum ConversionError: LocalizedError {
    case noInput
    case unreadable
    case writeFailed
    case nothingToConvert
    case noSavings
    case noEncoder
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInput:
            return String(localized: "Nothing to convert")
        case .unreadable:
            return String(localized: "The document could not be read")
        case .writeFailed:
            return String(localized: "The converted file could not be written")
        case .nothingToConvert:
            return String(localized: "No text was found in the document")
        case .noSavings:
            return String(localized: "The document cannot be made smaller without losing quality")
        case .noEncoder:
            return String(localized: "No encoder is available for this video")
        case .exportFailed(let message):
            return message
        }
    }
}
