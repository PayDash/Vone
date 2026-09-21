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
import Defaults
import SwiftUI

/// Controls for the floating Basket, shown alongside the Shelf settings.
struct BasketSettingsSection: View {
    @Default(.enableBasket) private var enableBasket
    @Default(.basketRevealMode) private var revealMode
    @Default(.basketShakeSensitivity) private var sensitivity
    @Default(.basketAppearDelay) private var appearDelay
    @Default(.basketHideDelay) private var hideDelay

    var body: some View {
        Section {
            Defaults.Toggle(key: .enableBasket) {
                Text("Enable Basket")
            }

            if enableBasket {
                Picker("Reveal basket", selection: $revealMode) {
                    ForEach(BasketRevealMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if revealMode == .shake {
                    Picker("Shake sensitivity", selection: $sensitivity) {
                        ForEach(BasketShakeSensitivity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }

                Slider(value: $appearDelay, in: 0...1, step: 0.05) {
                    HStack {
                        Text("Appear delay")
                        Spacer()
                        Text(appearDelay == 0 ? "Instant" : "\(appearDelay, specifier: "%.2f")s")
                            .foregroundStyle(.secondary)
                    }
                }

                Slider(value: $hideDelay, in: 0...5, step: 0.5) {
                    HStack {
                        Text("Close an empty basket after")
                        Spacer()
                        Text(hideDelay == 0 ? "Never" : "\(hideDelay, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .basketFollowsCursor) {
                    Text("Keep the basket under the pointer")
                }

                Defaults.Toggle(key: .basketAllowsMultiple) {
                    Text("Allow more than one basket")
                }

                Defaults.Toggle(key: .basketDismissesWhenEmptied) {
                    Text("Close a basket as soon as it is emptied")
                }
            }
        } header: {
            Text("Basket")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shake the pointer while dragging a file to bring a floating tray to the cursor. Files can be sent on to the Shelf, or straight to a Quick Action, without being dropped anywhere first.")

                Text(shortcutHint)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var shortcutHint: String {
        if Defaults[.basketRevealMode] == .shortcut {
            return String(localized: "The tray only appears when the Basket shortcut is pressed, and the same shortcut closes the front tray again. Escape closes it too. An empty tray also goes away when you click outside it.")
        }
        return String(localized: "The Basket shortcut (Ctrl+Option+B by default, changeable under Shortcuts) opens a tray without dragging, and closes the front one. Escape closes it too, and an empty tray goes away when you click outside it.")
    }
}
#endif
