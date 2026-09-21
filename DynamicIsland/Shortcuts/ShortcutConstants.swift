/*
 * Vone (DynamicIsland)
 * Copyright (C) 2024-2026 Vone Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Vone (DynamicIsland)
 * See NOTICE for details.
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

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.v, modifiers: [.shift, .command]))
    static let colorPickerPanel = Self("colorPickerPanel", default: .init(.p, modifiers: [.shift, .command]))
    static let screenAssistantPanel = Self("screenAssistantPanel", default: .init(.a, modifiers: [.shift, .command]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let toggleTerminalTab = Self("toggleTerminalTab", default: .init(.backtick, modifiers: [.control]))
    static let startDemoTimer = Self("startDemoTimer", default: .init(.t, modifiers: [.command, .shift]))
    static let toggleCaffeinate = Self("toggleCaffeinate", default: .init(.k, modifiers: [.command, .shift]))
    static let emojiPicker = Self("emojiPicker", default: .init(.e, modifiers: [.command, .shift]))
    static let ringActions = Self("ringActions", default: .init(.r, modifiers: [.control, .option]))
    static let toggleBasket = Self("toggleBasket", default: .init(.b, modifiers: [.control, .option]))
    static let snapLeft = Self("snapLeft", default: .init(.leftArrow, modifiers: [.control, .option]))
    static let snapRight = Self("snapRight", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let snapTop = Self("snapTop", default: .init(.upArrow, modifiers: [.control, .option]))
    static let snapBottom = Self("snapBottom", default: .init(.downArrow, modifiers: [.control, .option]))
    static let snapMaximize = Self("snapMaximize", default: .init(.return, modifiers: [.control, .option]))
    static let snapTopLeft = Self("snapTopLeft", default: .init(.one, modifiers: [.control, .option]))
    static let snapTopRight = Self("snapTopRight", default: .init(.two, modifiers: [.control, .option]))
    static let snapBottomLeft = Self("snapBottomLeft", default: .init(.three, modifiers: [.control, .option]))
    static let snapBottomRight = Self("snapBottomRight", default: .init(.four, modifiers: [.control, .option]))
    static let snapCenter = Self("snapCenter", default: .init(.c, modifiers: [.control, .option]))
}
