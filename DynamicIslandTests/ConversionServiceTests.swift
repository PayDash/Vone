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
import PDFKit
import XCTest
@testable import Vone

/// The converter is offered to the user only when it can really do the job, so the
/// two things that matter are: it recognises the right files, and what it writes is
/// a valid document rather than a plausible-looking file.
@MainActor
final class ConversionServiceTests: XCTestCase {

    private let service = ConversionService.shared
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("VoneConversionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        try super.tearDownWithError()
    }

    // MARK: Fixtures

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A PDF whose pages are images, which is what the size reducer is for.
    private func makeImagePDF(pages: Int, size: CGSize = CGSize(width: 400, height: 600)) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pages {
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(calibratedRed: CGFloat(index) / CGFloat(max(pages, 1)), green: 0.4, blue: 0.7, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor.white.setFill()
            NSRect(x: 20, y: 20, width: size.width - 40, height: 60).fill()
            image.unlockFocus()
            if let page = PDFPage(image: image) {
                document.insert(page, at: index)
            }
        }
        let url = scratch.appendingPathComponent("source-\(UUID().uuidString).pdf")
        XCTAssertTrue(document.write(to: url), "Could not build the fixture PDF")
        return url
    }

    // MARK: Classification

    func testRecognisesPDFAndRejectsAPlainTextFile() throws {
        let pdf = try makeImagePDF(pages: 1)
        let text = try write("notes.txt", "hello")

        XCTAssertTrue(service.isPDF(pdf))
        XCTAssertFalse(service.isPDF(text))
    }

    func testVideoIsRecognisedByType() throws {
        let movie = scratch.appendingPathComponent("clip.mp4")
        try Data(repeating: 0, count: 64).write(to: movie)

        XCTAssertTrue(service.isVideo(movie))
    }

    /// A folder or an unrecognised binary must not be offered as a document, or
    /// the Convert tile would appear next to files it cannot read.
    func testConvertibleDocumentsIncludeTextAndPDFButNotBinaries() throws {
        let text = try write("notes.txt", "hello")
        let markdown = try write("notes.md", "# heading")
        let rtf = try write("notes.rtf", "{\\rtf1\\ansi hello}")
        let binary = scratch.appendingPathComponent("blob.bin")
        try Data(repeating: 0xAB, count: 32).write(to: binary)
        let folder = scratch.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertTrue(service.isConvertibleDocument(text))
        XCTAssertTrue(service.isConvertibleDocument(markdown))
        XCTAssertTrue(service.isConvertibleDocument(rtf))
        XCTAssertFalse(service.isConvertibleDocument(binary))
        XCTAssertFalse(service.isConvertibleDocument(folder))
    }

    // MARK: Documents → PDF

    func testSingleDocumentBecomesAReadablePDF() async throws {
        let text = try write("letter.txt", "Hello from the Shelf.")

        let output = try await service.makePDF(fromDocuments: [text])

        XCTAssertEqual(output.pathExtension, "pdf")
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue((document.string ?? "").contains("Hello from the Shelf."))
    }

    /// A document longer than one page has to paginate rather than be clipped: a
    /// silently truncated conversion is worse than a failed one.
    func testLongDocumentPaginates() async throws {
        let body = (1...400).map { "Line \($0) of a document that must not be clipped." }.joined(separator: "\n")
        let text = try write("long.txt", body)

        let output = try await service.makePDF(fromDocuments: [text])

        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertGreaterThan(document.pageCount, 1)
        let all = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(all.contains("Line 400"), "The tail of the document is missing")
    }

    func testManyDocumentsShareOnePDFInOrder() async throws {
        let first = try write("a.txt", "First document marker.")
        let second = try write("b.txt", "Second document marker.")

        let output = try await service.makePDF(fromDocuments: [first, second])

        let document = try XCTUnwrap(PDFDocument(url: output))
        let all = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        let firstIndex = try XCTUnwrap(all.range(of: "First document marker.")?.lowerBound)
        let secondIndex = try XCTUnwrap(all.range(of: "Second document marker.")?.lowerBound)
        XCTAssertLessThan(firstIndex, secondIndex)
    }

    func testEmptySelectionIsRejected() async {
        do {
            _ = try await service.makePDF(fromDocuments: [])
            XCTFail("Converting nothing must not produce a file")
        } catch {
            XCTAssertTrue(error is ConversionError)
        }
    }

    // MARK: Text out

    func testTextIsExtractedFromADocument() async throws {
        let text = try write("notes.txt", "  Extract me.  ")

        let output = try await service.makeText(from: [text])

        XCTAssertEqual(output.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "Extract me.")
    }

    func testTextIsExtractedFromAPDF() async throws {
        let source = try write("letter.txt", "Text inside a PDF.")
        let pdf = try await service.makePDF(fromDocuments: [source])

        let output = try await service.makeText(from: [pdf])

        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).contains("Text inside a PDF."))
    }

    func testSeveralInputsProduceOneTextFile() async throws {
        let first = try write("a.txt", "alpha")
        let second = try write("b.txt", "beta")

        let output = try await service.makeText(from: [first, second])

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "alpha\n\nbeta")
    }

    func testDocumentWithoutTextFails() async throws {
        let blank = try write("blank.txt", "   \n  ")

        do {
            _ = try await service.makeText(from: [blank])
            XCTFail("A document with no text cannot produce a text file")
        } catch {
            XCTAssertEqual((error as? ConversionError)?.errorDescription, ConversionError.nothingToConvert.errorDescription)
        }
    }

    // MARK: Documents → other formats

    func testDocumentConvertsToRichTextAndHTML() async throws {
        let text = try write("notes.txt", "Formatted body.")

        for format in [ConversionService.TextFormat.richText, .html] {
            let output = try await service.makeDocument(from: text, as: format)
            XCTAssertEqual(output.pathExtension, format.fileExtension)
            let produced = try String(contentsOf: output, encoding: .utf8)
            XCTAssertGreaterThan(produced.count, 0)
        }
    }

    func testPDFFormatRoutesThroughThePDFWriter() async throws {
        let text = try write("notes.txt", "Body.")

        let output = try await service.makeDocument(from: text, as: .pdf)

        XCTAssertNotNil(PDFDocument(url: output))
    }

    // MARK: Reduce PDF size

    /// Either the file really gets smaller or the conversion refuses — never a
    /// "compressed" file that is larger than the original, and never a corrupt one.
    func testReducePDFSizeShrinksOrRefuses() async throws {
        let source = try makeImagePDF(pages: 2)
        let originalSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64)
        let originalPages = try XCTUnwrap(PDFDocument(url: source)).pageCount

        do {
            let output = try await service.reducePDFSize(at: source, level: .maximum)
            let outputSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64)

            XCTAssertLessThan(outputSize, originalSize)
            XCTAssertEqual(try XCTUnwrap(PDFDocument(url: output)).pageCount, originalPages, "A page was lost")
        } catch ConversionError.noSavings {
            // Legitimate for an already-optimised document.
        }
    }

    /// A refusal must not leave a half-written file behind for the Shelf to pick up.
    func testRefusedCompressionLeavesNoOutputBehind() async throws {
        // A tiny vector-free page has nothing worth re-encoding.
        let source = try makeImagePDF(pages: 1, size: CGSize(width: 40, height: 40))
        let before = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()

        _ = try? await service.reducePDFSize(at: source, level: .maximum)

        let after = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()
        XCTAssertEqual(before, after, "The refused conversion left a file in the destination")
    }

    func testUnreadableInputIsRejected() async throws {
        let notAPDF = try write("fake.pdf", "this is not a pdf")

        do {
            _ = try await service.reducePDFSize(at: notAPDF, level: .balanced)
            XCTFail("A non-PDF must not convert")
        } catch {
            XCTAssertTrue(error is ConversionError)
        }
    }

    // MARK: Video

    /// A file that only looks like a video fails loudly instead of producing an
    /// empty movie the user would find later.
    func testNonVideoInputFailsInsteadOfProducingAFile() async throws {
        let fake = scratch.appendingPathComponent("clip.mp4")
        try Data(repeating: 0, count: 1024).write(to: fake)
        let before = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()

        do {
            _ = try await service.compressVideo(at: fake, target: .tenMegabytes)
            XCTFail("A file with no video track must not export")
        } catch {
            XCTAssertTrue(error is ConversionError)
        }

        let after = try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()
        XCTAssertEqual(before, after)
    }

    // MARK: Options

    /// Higher quality means more dots per inch and a higher JPEG factor; a swapped
    /// mapping would quietly turn "Light" into the lossiest setting.
    func testCompressionLevelsAreOrdered() {
        let levels: [ConversionService.CompressionLevel] = [.light, .balanced, .maximum]

        XCTAssertEqual(levels.map(\.dpi), levels.map(\.dpi).sorted(by: >))
        XCTAssertEqual(levels.map(\.jpegQuality), levels.map(\.jpegQuality).sorted(by: >))
        XCTAssertEqual(Set(levels.map(\.title)).count, levels.count)
    }

    func testVideoTargetsAreDistinctAndReadable() {
        let targets = ConversionService.VideoTarget.allCases

        XCTAssertEqual(Set(targets.map(\.rawValue)).count, targets.count)
        XCTAssertEqual(Set(targets.map(\.title)).count, targets.count)
        for target in targets {
            XCTAssertTrue(target.title.contains("MB"), "\(target.title) is not a size a user can recognise")
        }
    }

    func testTextFormatsMapToTheRightExtensions() {
        XCTAssertEqual(ConversionService.TextFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ConversionService.TextFormat.plainText.fileExtension, "txt")
        XCTAssertEqual(ConversionService.TextFormat.richText.fileExtension, "rtf")
        XCTAssertEqual(ConversionService.TextFormat.html.fileExtension, "html")
    }

    // MARK: The tile's entry point

    /// The Convert tile and the Shelf menu share this check, so what it accepts
    /// decides whether the tile is offered at all.
    func testCanConvertMatchesWhatTheServiceHandles() throws {
        let pdf = try makeImagePDF(pages: 1)
        let text = try write("notes.txt", "hello")
        let movie = scratch.appendingPathComponent("clip.mp4")
        try Data(repeating: 0, count: 64).write(to: movie)
        let binary = scratch.appendingPathComponent("blob.bin")
        try Data(repeating: 0xAB, count: 32).write(to: binary)

        XCTAssertTrue(ConversionActions.canConvert([pdf]))
        XCTAssertTrue(ConversionActions.canConvert([text]))
        XCTAssertTrue(ConversionActions.canConvert([movie]))
        XCTAssertTrue(ConversionActions.canConvert([binary, pdf]), "One convertible file is enough")
        XCTAssertFalse(ConversionActions.canConvert([binary]))
        XCTAssertFalse(ConversionActions.canConvert([]))
    }
}
