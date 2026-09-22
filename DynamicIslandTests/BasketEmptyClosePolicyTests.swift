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

/// An empty tray that closes the moment the mouse comes up is a tray the user
/// never gets to put anything in. These tests pin the rule that decides when an
/// empty tray may be tidied away, because the bug it fixes was exactly a timing
/// bug: the tray vanished between the shake and the file being carried to it.
final class BasketEmptyClosePolicyTests: XCTestCase {

    /// Shake while dragging → the tray appears → the mouse comes up. The tray was
    /// just asked for, so that drag ending must not take it away.
    func testTraySummonedDuringADragSurvivesThatDrag() {
        var policy = BasketEmptyClosePolicy()

        policy.noteSummon()

        XCTAssertFalse(policy.shouldTidyEmptyTraysAfterDrag())
    }

    /// The next drag that ends with the tray still empty is a stale tray, and the
    /// grace is spent: one drag of it, not forever.
    func testTheFollowingDragTidiesItAway() {
        var policy = BasketEmptyClosePolicy()
        policy.noteSummon()

        XCTAssertFalse(policy.shouldTidyEmptyTraysAfterDrag())
        XCTAssertTrue(policy.shouldTidyEmptyTraysAfterDrag(), "a tray nobody used should not be kept forever")
    }

    func testATrayThatPredatesTheDragIsTidied() {
        var policy = BasketEmptyClosePolicy()

        XCTAssertTrue(policy.shouldTidyEmptyTraysAfterDrag(), "no summon means nothing to protect")
    }

    func testTidyingStaysAgreedOnceSpent() {
        var policy = BasketEmptyClosePolicy()
        policy.noteSummon()
        _ = policy.shouldTidyEmptyTraysAfterDrag()

        XCTAssertTrue(policy.shouldTidyEmptyTraysAfterDrag())
        XCTAssertTrue(policy.shouldTidyEmptyTraysAfterDrag())
    }

    /// Summoning again — a second shake, or the shortcut — buys the tray another
    /// drag of grace rather than being ignored because one was already spent.
    func testEachSummonBuysItsOwnGrace() {
        var policy = BasketEmptyClosePolicy()

        for _ in 0..<3 {
            policy.noteSummon()
            XCTAssertFalse(policy.shouldTidyEmptyTraysAfterDrag())
        }
    }
}
