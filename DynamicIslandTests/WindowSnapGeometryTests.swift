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

/// Snapping is arithmetic on screen coordinates, and every mistake it can make --
/// a half that overlaps the other half, a quarter that hangs off the display, a
/// conversion that flips the wrong way -- is invisible until a window lands in the
/// wrong place on hardware nobody testing it owns.
final class WindowSnapGeometryTests: XCTestCase {
    /// A display's usable area, and one with a negative origin the way a second
    /// display to the left of the main one is laid out.
    private let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
    private let offCentreDisplay = NSRect(x: -1920, y: 120, width: 1920, height: 1080)

    func testHalvesTileTheDisplayWithoutOverlapping() {
        let left = WindowSnapManager.targetFrame(.leftHalf, in: visible)
        let right = WindowSnapManager.targetFrame(.rightHalf, in: visible)

        XCTAssertEqual(left.maxX, right.minX, accuracy: 0.001)
        XCTAssertEqual(left.width, visible.width / 2, accuracy: 0.001)
        XCTAssertEqual(right.width, visible.width / 2, accuracy: 0.001)
        XCTAssertEqual(left.height, visible.height, accuracy: 0.001)

        let top = WindowSnapManager.targetFrame(.topHalf, in: visible)
        let bottom = WindowSnapManager.targetFrame(.bottomHalf, in: visible)

        XCTAssertEqual(bottom.maxY, top.minY, accuracy: 0.001)
        XCTAssertEqual(top.height, visible.height / 2, accuracy: 0.001)
        XCTAssertEqual(bottom.height, visible.height / 2, accuracy: 0.001)
    }

    func testQuartersMeetAtTheCentreOfTheDisplay() {
        let centre = CGPoint(x: visible.midX, y: visible.midY)
        let quarters: [SnapPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

        for position in quarters {
            let frame = WindowSnapManager.targetFrame(position, in: visible)

            XCTAssertEqual(frame.width, visible.width / 2, accuracy: 0.001, "\(position)")
            XCTAssertEqual(frame.height, visible.height / 2, accuracy: 0.001, "\(position)")

            // Each quarter must reach the centre, or the four of them leave a
            // cross-shaped gap no window ever lands in.
            XCTAssertTrue(frame.minX <= centre.x && frame.maxX >= centre.x, "\(position) does not reach the centre horizontally")
            XCTAssertTrue(frame.minY <= centre.y && frame.maxY >= centre.y, "\(position) does not reach the centre vertically")
        }

        XCTAssertEqual(
            WindowSnapManager.targetFrame(.topLeft, in: visible).maxX,
            WindowSnapManager.targetFrame(.topRight, in: visible).minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WindowSnapManager.targetFrame(.bottomLeft, in: visible).maxY,
            WindowSnapManager.targetFrame(.topLeft, in: visible).minY,
            accuracy: 0.001
        )
    }

    func testMaximiseFillsTheVisibleAreaExactly() {
        XCTAssertEqual(WindowSnapManager.targetFrame(.maximize, in: visible), visible)
    }

    /// Centre is a window, not a full screen: it has to be smaller than the
    /// display and an equal distance from every edge.
    func testCentreIsInsetAndCentred() {
        let frame = WindowSnapManager.targetFrame(.center, in: visible)

        XCTAssertLessThan(frame.width, visible.width)
        XCTAssertLessThan(frame.height, visible.height)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.001)
        XCTAssertTrue(visible.contains(frame))
    }

    func testEveryPositionStaysInsideADisplayAtANegativeOrigin() {
        for position in SnapPosition.allCases {
            let frame = WindowSnapManager.targetFrame(position, in: offCentreDisplay)

            XCTAssertTrue(
                offCentreDisplay.contains(frame),
                "\(position) falls outside the display at \(frame)"
            )
        }
    }

    /// Accessibility measures from the top-left of the primary display and AppKit
    /// from its bottom-left. A round trip has to come back where it started, or
    /// every snap lands mirrored vertically.
    func testCoordinateConversionRoundTrips() {
        let rects = [
            visible,
            NSRect(x: 40, y: 900, width: 200, height: 30),
            NSRect(x: -1500, y: 200, width: 640, height: 480),
        ]

        for rect in rects {
            let back = WindowSnapManager.convertToCocoa(WindowSnapManager.convertToAX(rect))
            XCTAssertEqual(back.origin.x, rect.origin.x, accuracy: 0.001)
            XCTAssertEqual(back.origin.y, rect.origin.y, accuracy: 0.001)
            XCTAssertEqual(back.width, rect.width, accuracy: 0.001)
            XCTAssertEqual(back.height, rect.height, accuracy: 0.001)
        }
    }

    /// Accessibility y grows downwards where AppKit's grows upwards, so the upper
    /// half of the display has to end up with the smaller Accessibility y. The
    /// absolute offset depends on the primary display's height, which is why this
    /// compares the two halves with each other rather than measuring from zero.
    func testUpperHalfHasTheSmallerAccessibilityY() {
        let top = WindowSnapManager.convertToAX(WindowSnapManager.targetFrame(.topHalf, in: visible))
        let bottom = WindowSnapManager.convertToAX(WindowSnapManager.targetFrame(.bottomHalf, in: visible))

        XCTAssertLessThan(top.minY, bottom.minY)
        XCTAssertEqual(bottom.minY, top.maxY, accuracy: 0.001)
    }
}
