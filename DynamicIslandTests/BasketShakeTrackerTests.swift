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

/// The basket opens when the pointer is shaken mid-drag. Getting the threshold
/// wrong is felt rather than seen: too loose and a tray flashes up during ordinary
/// dragging, too tight and the gesture never works, and neither is reproducible by
/// hand.
final class BasketShakeTrackerTests: XCTestCase {
    /// A drag in one direction never looks like a shake, however far it goes.
    func testStraightDragDoesNotFire() {
        var tracker = BasketShakeTracker()
        var fired = false

        for step in 1...40 {
            if tracker.register(x: CGFloat(step) * 20, at: 10 + Double(step) * 0.02, sensitivity: .medium) {
                fired = true
            }
        }

        XCTAssertFalse(fired)
    }

    /// Being still, or barely moving, is not a shake either -- a shaky hand
    /// nudging the pointer by a point does not count as a swing.
    func testAStillPointerDoesNotFire() {
        var tracker = BasketShakeTracker()
        var fired = false

        for step in 0..<60 {
            let x = CGFloat(500 + (step % 2 == 0 ? 0 : 0.2))
            if tracker.register(x: x, at: 10 + Double(step) * 0.05, sensitivity: .veryHigh) {
                fired = true
            }
        }

        XCTAssertFalse(fired)
    }

    /// The gesture that is supposed to work does work: four swings of more than
    /// the minimum travel, close together, at the default sensitivity.
    func testRepeatedReversalsFire() {
        var tracker = BasketShakeTracker()
        let positions: [CGFloat] = [500, 530, 500, 530, 500, 530]
        var fired = false

        for (index, x) in positions.enumerated() {
            if tracker.register(x: x, at: 10 + Double(index) * 0.05, sensitivity: .medium) {
                fired = true
            }
        }

        XCTAssertTrue(fired)
    }

    /// A reversal only counts once the pointer has actually travelled; jittering
    /// around one spot a few times is not a shake.
    func testReversalsBelowTheTravelThresholdDoNotFire() {
        var tracker = BasketShakeTracker()
        let positions: [CGFloat] = [500, 504, 500, 504, 500, 504, 500, 504, 500, 504]
        var fired = false

        for (index, x) in positions.enumerated() {
            if tracker.register(x: x, at: 10 + Double(index) * 0.05, sensitivity: .medium) {
                fired = true
            }
        }

        XCTAssertFalse(fired)
    }

    /// The low-sensitivity setting is a deliberate, larger shake: more reversals
    /// and more travel each way before it counts.
    func testSensitivityChangesWhatCounts() {
        // Two reversals of 20 points is enough for very high, not for low.
        let positions: [CGFloat] = [500, 520, 500, 520, 500]

        func fires(_ sensitivity: BasketShakeSensitivity) -> Bool {
            var tracker = BasketShakeTracker()
            var fired = false
            for (index, x) in positions.enumerated() {
                if tracker.register(x: x, at: 10 + Double(index) * 0.05, sensitivity: sensitivity) {
                    fired = true
                }
            }
            return fired
        }

        XCTAssertTrue(fires(.veryHigh))
        XCTAssertFalse(fires(.low))
    }

    /// A pause ends the streak: wiggles spread over several seconds are someone
    /// dragging, not someone asking for a tray.
    func testAPauseEndsTheStreak() {
        var tracker = BasketShakeTracker()
        var fired = false

        // Three quick swings.
        for (index, x) in [CGFloat(500), 530, 500, 530].enumerated() {
            if tracker.register(x: x, at: 10 + Double(index) * 0.05, sensitivity: .medium) { fired = true }
        }

        // Then a long gap, then a single swing. Without the window this fourth
        // reversal would complete the count and open the tray.
        var time: TimeInterval = 14
        for x in [CGFloat(500), 530, 500] {
            if tracker.register(x: x, at: time, sensitivity: .medium) { fired = true }
            time += 0.05
        }

        XCTAssertFalse(fired)
    }

    /// Once the shake fires the count starts over, so the swing right after a
    /// fire cannot immediately count as the start of another shake.
    func testTrackerRearmsAfterFiring() {
        var tracker = BasketShakeTracker()
        var time: TimeInterval = 10
        var x: CGFloat = 500
        var fired = false

        for _ in 0..<6 {
            if tracker.register(x: x, at: time, sensitivity: .medium) { fired = true }
            x = x <= 500 ? 530 : 500
            time += 0.05
        }

        XCTAssertTrue(fired, "Four swings should have opened the tray by now")

        var firedAgain = false
        for _ in 0..<2 {
            if tracker.register(x: x, at: time, sensitivity: .medium) { firedAgain = true }
            x = x <= 500 ? 530 : 500
            time += 0.05
        }

        XCTAssertFalse(firedAgain)
    }
}
