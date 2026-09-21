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
import Combine
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let emojiPickerRecents = Key<[String]>("emojiPickerRecents", default: [])
    static let enableEmojiPicker = Key<Bool>("enableEmojiPicker", default: true)
}

/// Floating emoji panel. Opening it does not activate Vone, and choosing an emoji
/// types it into whatever app was frontmost when the panel opened.
final class EmojiPickerManager: ObservableObject {
    static let shared = EmojiPickerManager()

    static let panelSize = CGSize(width: 320, height: 300)

    @Published var query: String = ""
    @Published var selectedCategory: EmojiCategory = .smileys
    @Published private(set) var recents: [String] = Defaults[.emojiPickerRecents]

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private weak var previousApp: NSRunningApplication?

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: Presentation

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        query = ""
        if recents.isEmpty { selectedCategory = .smileys }

        let panel = existingPanelOrNew()
        positionNearPointer(panel)

        panel.makeKeyAndOrderFront(nil)
        installEscapeMonitor()
    }

    func hide() {
        removeEscapeMonitor()
        panel?.orderOut(nil)
        // Hand focus back so typing resumes in the app the user came from.
        previousApp?.activate()
    }

    // MARK: Selection

    func select(_ emoji: String) {
        remember(emoji)
        hide()

        // Give the previous app a moment to become frontmost again before the
        // synthetic key events are posted, otherwise they land in the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.typeIntoFocusedApp(emoji)
        }
    }

    private func remember(_ emoji: String) {
        var updated = Defaults[.emojiPickerRecents]
        updated.removeAll { $0 == emoji }
        updated.insert(emoji, at: 0)
        if updated.count > 24 { updated = Array(updated.prefix(24)) }
        Defaults[.emojiPickerRecents] = updated
        recents = updated
    }

    /// Posts the emoji as a unicode key event. Requires Accessibility, which Vone
    /// already asks for.
    static func typeIntoFocusedApp(_ emoji: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(emoji.utf16)
        guard !utf16.isEmpty else { return }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: Panel plumbing

    private func existingPanelOrNew() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: EmojiPickerView())

        self.panel = panel
        return panel
    }

    private func positionNearPointer(_ panel: NSPanel) {
        let point = NSEvent.mouseLocation
        let size = Self.panelSize
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height - 16)

        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        panel.setFrameOrigin(origin)
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Escape
                self.hide()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }
}
#endif
