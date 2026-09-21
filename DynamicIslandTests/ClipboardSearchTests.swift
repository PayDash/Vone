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

import XCTest

@testable import Vone

/// A copied screenshot previews as "Image (240 KB)" — the one label a search
/// for the words on screen can never match. These pin the behaviour that fixes
/// it, and the decode path that keeps histories written before it existed
/// readable.
final class ClipboardSearchTests: XCTestCase {
    private func textItem(_ preview: String) -> ClipboardItem {
        ClipboardItem(stringData: preview, type: .text)
    }

    private func imageItem(ocrText: String?) -> ClipboardItem {
        var item = ClipboardItem(stringData: "", type: .image)
        item.ocrText = ocrText
        return item
    }

    // MARK: - What a search matches

    func testSearchMatchesThePreview() {
        XCTAssertTrue(textItem("invoice-2026.pdf").matches("invoice"))
    }

    func testSearchMatchesTheTypeName() {
        XCTAssertTrue(textItem("something else").matches("Text"))
    }

    /// The point of the field: words inside a copied image are findable.
    func testSearchMatchesTextRecognisedInsideAnImage() {
        let item = imageItem(ocrText: "Total due 42.00 EUR")
        XCTAssertTrue(item.matches("42.00"), "recognised text should be searchable")
        XCTAssertTrue(item.matches("total due"), "matching should not care about case")
    }

    /// …and an image with nothing extracted still behaves like any other entry.
    func testImageWithoutRecognisedTextIsStillFoundByItsLabel() {
        let item = imageItem(ocrText: nil)
        XCTAssertTrue(item.matches("Image"))
        XCTAssertFalse(item.matches("42.00"))
    }

    func testUnrelatedQueryDoesNotMatch() {
        XCTAssertFalse(imageItem(ocrText: "Total due 42.00 EUR").matches("recipe"))
    }

    /// The entry rows call this with whatever is in the field, including the
    /// blank string and a stray space. An empty field is not a filter.
    func testEmptyQueryMatchesEverything() {
        let item = textItem("anything")
        XCTAssertTrue(item.matches(""))
        XCTAssertTrue(item.matches("   "))
        XCTAssertTrue(item.matches("\n"))
    }

    /// A trailing space is left by the field constantly; it should not turn a
    /// match into a miss.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertTrue(textItem("invoice-2026.pdf").matches("  invoice  "))
    }

    // MARK: - Stored history

    /// Histories saved before the field existed must still decode — a
    /// non-optional field here would throw the whole history away on upgrade.
    /// The payload is built by removing the key from a current one rather than
    /// hand-writing last release's shape, so it stays honest if the struct
    /// gains another field.
    func testDecodesHistoryWrittenBeforeRecognisedTextExisted() throws {
        var item = imageItem(ocrText: "Total due 42.00 EUR")
        item.isPinned = true

        let encoded = try JSONEncoder().encode(item)
        guard var payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return XCTFail("an encoded item should be a JSON object")
        }
        XCTAssertNotNil(payload.removeValue(forKey: "ocrText"), "expected the key to strip")

        let legacy = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: legacy)

        XCTAssertNil(decoded.ocrText)
        XCTAssertEqual(decoded.preview, item.preview)
        XCTAssertTrue(decoded.matches("Image"))
        XCTAssertFalse(decoded.matches("42.00"), "without the text there is nothing to match")
    }

    /// Recognised text survives a round trip, so a restart does not require
    /// running the image through Vision again.
    func testRecognisedTextSurvivesARoundTrip() throws {
        let item = imageItem(ocrText: "Total due 42.00 EUR")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertEqual(decoded.ocrText, "Total due 42.00 EUR")
    }
}
