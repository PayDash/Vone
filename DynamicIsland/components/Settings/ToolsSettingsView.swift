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

/// Settings for the pointer tools: the emoji panel, the action ring, window
/// snapping and on-device text recognition.
///
/// All four are shortcut-first, so this page exists mainly so the features can be
/// found -- and turned off by anyone who does not want a global shortcut they never
/// asked for. Which key opens what lives on the Shortcuts page; the toggles here
/// decide whether this app listens at all.
struct ToolsSettingsView: View {
    @Default(.enableEmojiPicker) private var enableEmojiPicker
    @Default(.enableRingActions) private var enableRingActions
    @Default(.enableWindowSnap) private var enableWindowSnap
    @Default(.enableOCR) private var enableOCR
    @Default(.ocrPreservesLineBreaks) private var preservesLineBreaks
    @Default(.ocrShowsConfirmation) private var showsConfirmation
    @Default(.ocrOpensEditor) private var opensEditor

    @ObservedObject private var accessibility = AccessibilityPermissionStore.shared

    /// Matches `SettingsTab.tools.highlightID(for:)`. The tab enum is private to
    /// the settings window's own file, so the prefix is spelled out here; the
    /// search index uses this same helper for its entries.
    private func highlightID(_ title: String) -> String {
        "tools-\(title)"
    }

    var body: some View {
        Form {
            emojiPickerSection
            ringSection
            windowSnapSection
            ocrSection
        }
    }

    // MARK: Emoji

    private var emojiPickerSection: some View {
        Section {
            Defaults.Toggle(key: .enableEmojiPicker) {
                Text("Enable emoji picker")
            }
            .settingsHighlight(id: highlightID("Enable emoji picker"))
        } header: {
            Text("Emoji Picker")
        } footer: {
            Text("A floating panel with search, categories and your recent emoji. The emoji is typed into whichever app you were using. Set its shortcut under Shortcuts.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Ring

    private var ringSection: some View {
        Section {
            Defaults.Toggle(key: .enableRingActions) {
                Text("Enable the action ring")
            }
            .settingsHighlight(id: highlightID("Enable the action ring"))
        } header: {
            Text("Action Ring")
        } footer: {
            Text("A ring of actions around the pointer: emoji, colour picker, a new basket and text recognition. Escape or a click anywhere else puts it away.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Window Snap

    private var windowSnapSection: some View {
        Section {
            if !accessibility.isAuthorized {
                SettingsPermissionCallout(
                    message: String(localized: "Window snapping moves the focused window through the Accessibility API, which this app is not allowed to use yet."),
                    requestAction: { accessibility.requestAuthorizationPrompt() },
                    openSettingsAction: { accessibility.openSystemSettings() }
                )
            }

            Defaults.Toggle(key: .enableWindowSnap) {
                Text("Enable window snapping")
            }
            .settingsHighlight(id: highlightID("Enable window snapping"))
        } header: {
            Text("Window Snap")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Halves, quarters, maximise and centre, applied to the focused window of whichever app is in front. Each position has its own shortcut on the Shortcuts page; the defaults are Ctrl+Option with an arrow key, a number 1-4 for the quarters, Return for maximise and C for centre.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: OCR

    private var ocrSection: some View {
        Section {
            Defaults.Toggle(key: .enableOCR) {
                Text("Enable text recognition")
            }
            .settingsHighlight(id: highlightID("Enable text recognition"))

            if enableOCR {
                Defaults.Toggle(key: .ocrPreservesLineBreaks) {
                    Text("Keep line breaks")
                }
                .settingsHighlight(id: highlightID("Keep line breaks"))

                Defaults.Toggle(key: .ocrShowsConfirmation) {
                    Text("Show the result panel")
                }

                Defaults.Toggle(key: .ocrOpensEditor) {
                    Text("Open the result in a text editor")
                }
                .settingsHighlight(id: highlightID("Open the result in a text editor"))
            }
        } header: {
            Text("Text Recognition")
        } footer: {
            Text("Recognises text on device: a screen region, an image, or the first pages of a PDF. The result is copied to the clipboard. The OCR tile in a basket or on the Shelf works on whatever is dropped on it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
