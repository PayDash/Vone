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
import Defaults
import SwiftUI

extension Defaults.Keys {
    static let enableRingActions = Key<Bool>("enableRingActions", default: true)
}

/// One entry in the radial menu.
struct RingAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let perform: () -> Void
}

/// Radial action menu shown at the pointer. Actions are picked from the centre of
/// the screen you are on, so the ring works identically on every display.
final class RingActionManager: ObservableObject {
    static let shared = RingActionManager()

    /// Diameter of the visible ring, and the circle the tiles are laid out on.
    static let ringDiameter: CGFloat = 168
    static let radius: CGFloat = 92
    /// Half-width of one tile. A tile sits at `radius` from the centre, so the
    /// panel only has to reach `radius + tileReach` in every direction -- a panel
    /// any larger than that is empty space that swallows clicks meant for the app
    /// behind it.
    private static let tileReach: CGFloat = 28
    static let panelSize = CGSize(
        width: (radius + tileReach) * 2,
        height: (radius + tileReach) * 2
    )

    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var outsideClickMonitor: Any?

    private init() {}

    var actions: [RingAction] {
        [
            RingAction(id: "emoji", title: "Emoji", systemImage: "face.smiling") {
                EmojiPickerManager.shared.toggle()
            },
            RingAction(id: "color", title: String(localized: "Colour"), systemImage: "eyedropper") {
                ColorPickerManager.shared.toggleColorPicker()
            },
            RingAction(id: "basket", title: "Basket", systemImage: "tray.full") {
                BasketManager.shared.reveal(at: NSEvent.mouseLocation)
            },
            RingAction(id: "ocr", title: "OCR", systemImage: "text.viewfinder") {
                OCRService.shared.captureRegionAndRecognize()
            },
        ]
    }

    // MARK: Presentation

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = existingPanelOrNew()
        positionAtPointer(panel)
        // The ring takes key focus so its own Escape monitor is deliverable: a
        // local monitor only sees keys while a Vone panel is key.
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installEscapeMonitor()
        installOutsideClickMonitor()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func hide() {
        removeEscapeMonitor()
        removeOutsideClickMonitor()
        panel?.orderOut(nil)
        isVisible = false
    }

    func perform(_ action: RingAction) {
        hide()
        DispatchQueue.main.async {
            action.perform()
        }
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
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: RingActionView())

        self.panel = panel
        return panel
    }

    private func positionAtPointer(_ panel: NSPanel) {
        let point = NSEvent.mouseLocation
        let size = Self.panelSize
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)

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

    /// Clicks anywhere outside the ring put it away. A global monitor sees the
    /// clicks that land in other apps, and this one only exists while the ring is
    /// up, so it never sits in front of an unrelated click.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}

// MARK: - View

/// Lays the actions out on a circle, starting at the top and going clockwise.
struct RingActionView: View {
    @ObservedObject private var manager = RingActionManager.shared
    @State private var hoveredID: String?
    @State private var pressedID: String?

    /// A tile's own frame. The release point arrives in the tile's coordinate
    /// space, so this is what tells a release on the tile from one that slid off
    /// it — and it is the same size the tile is laid out at, so the two cannot
    /// drift apart.
    private static let tileSize = CGSize(width: 52, height: 44)
    private static let tileBounds = CGRect(origin: .zero, size: tileSize)

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(
                    width: RingActionManager.ringDiameter,
                    height: RingActionManager.ringDiameter
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            ForEach(Array(manager.actions.enumerated()), id: \.element.id) { index, action in
                tile(action)
                    .offset(offset(for: index, of: manager.actions.count))
            }

            Image(systemName: "circle.grid.cross")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(width: RingActionManager.panelSize.width, height: RingActionManager.panelSize.height)
    }

    /// A sector is chosen by holding it and letting go, the way a pie menu
    /// works, rather than by a click landing on it.
    ///
    /// The difference is what a mis-aim costs. A click fires the moment the
    /// button goes down, so a press that rolled off the sector you meant has
    /// already opened the emoji picker or started a screen capture; here nothing
    /// happens until the button comes up, and if it comes up anywhere but on the
    /// sector it was pressed on, the ring stays where it is and you try again.
    /// Press and release without moving still selects, so the ordinary click
    /// keeps working.
    private func tile(_ action: RingAction) -> some View {
        let isHighlighted = hoveredID == action.id || pressedID == action.id

        return VStack(spacing: 2) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .medium))
            Text(action.title)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
        }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.28) : Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isHighlighted ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressedID = action.id
                    hoveredID = action.id
                }
                .onEnded { value in
                    pressedID = nil
                    guard Self.tileBounds.contains(value.location) else { return }
                    manager.perform(action)
                }
        )
        .onHover { hoveredID = $0 ? action.id : (hoveredID == action.id ? nil : hoveredID) }
        .accessibilityElement()
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
        .help(action.title)
    }

    private func offset(for index: Int, of count: Int) -> CGSize {
        guard count > 0 else { return .zero }
        // Start at 12 o'clock and walk clockwise.
        let angle = (Double(index) / Double(count)) * 2 * Double.pi - Double.pi / 2
        return CGSize(
            width: cos(angle) * RingActionManager.radius,
            height: sin(angle) * RingActionManager.radius
        )
    }
}
#endif
