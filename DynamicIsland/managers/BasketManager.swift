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

// MARK: - Settings types

/// How a floating basket is summoned while a drag is in progress.
enum BasketRevealMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case shake
    case instant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shake: return "Shake while dragging"
        case .instant: return "As soon as a drag starts"
        }
    }
}

/// How much wiggling counts as a deliberate shake.
enum BasketShakeSensitivity: String, CaseIterable, Defaults.Serializable, Identifiable {
    case low
    case medium
    case high
    case veryHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .veryHigh: return "Very high"
        }
    }

    /// Direction reversals required inside the shake window.
    var reversalsRequired: Int {
        switch self {
        case .low: return 5
        case .medium: return 4
        case .high: return 3
        case .veryHigh: return 2
        }
    }

    /// Minimum horizontal travel, in points, before a swing counts.
    var minimumTravel: CGFloat {
        switch self {
        case .low: return 26
        case .medium: return 18
        case .high: return 12
        case .veryHigh: return 8
        }
    }
}

extension Defaults.Keys {
    static let enableBasket = Key<Bool>("enableBasket", default: true)
    static let basketRevealMode = Key<BasketRevealMode>("basketRevealMode", default: .shake)
    static let basketShakeSensitivity = Key<BasketShakeSensitivity>("basketShakeSensitivity", default: .medium)
    static let basketAllowsMultiple = Key<Bool>("basketAllowsMultiple", default: false)
    static let basketDismissesWhenEmptied = Key<Bool>("basketDismissesWhenEmptied", default: true)
}

// MARK: - Model

/// One floating tray. Items are held with the same value type the Shelf uses so a
/// basket can hand a pile straight to the tray without converting anything.
struct Basket: Identifiable {
    let id: UUID
    var items: [TrayDrop.DropItem]
}

// MARK: - Manager

/// Presents floating trays next to the pointer. A tray is revealed by shaking the
/// pointer during a drag (or immediately, depending on preference) so a half-finished
/// pile of files has somewhere to wait that is not the top of the screen.
final class BasketManager: ObservableObject {
    static let shared = BasketManager()

    @Published private(set) var baskets: [Basket] = []

    private var panels: [UUID: NSPanel] = [:]
    private var monitors: [Any] = []

    // Drag + shake tracking. All of this is main-thread only, because NSEvent
    // monitors deliver on the main run loop.
    private var isDragging = false
    private var lastDragX: CGFloat?
    private var lastDirection: Int = 0
    private var travelSinceFlip: CGFloat = 0
    private var reversals = 0
    private var lastFlipTime: TimeInterval = 0
    private var lastRevealTime: TimeInterval = 0

    private static let shakeWindow: TimeInterval = 0.6
    private static let revealCooldown: TimeInterval = 0.7
    static let panelSize = CGSize(width: 248, height: 196)

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard monitors.isEmpty else { return }

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseUp, .rightMouseUp,
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        closeAll()
    }

    // MARK: Presentation

    /// Reveals a tray next to `screenPoint` (AppKit screen coordinates).
    func reveal(at screenPoint: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRevealTime > Self.revealCooldown else { return }
        lastRevealTime = now

        if !Defaults[.basketAllowsMultiple], let existing = baskets.first {
            positionPanel(for: existing.id, at: screenPoint)
            feedback()
            return
        }

        let basket = Basket(id: UUID(), items: [])
        baskets.append(basket)
        createPanel(for: basket.id)
        positionPanel(for: basket.id, at: screenPoint)
        feedback()
    }

    func close(basketID: UUID) {
        panels[basketID]?.orderOut(nil)
        panels[basketID] = nil
        baskets.removeAll { $0.id == basketID }
    }

    func closeAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        baskets.removeAll()
    }

    // MARK: Items

    func add(_ providers: [NSItemProvider], to basketID: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let urls = providers.interfaceConvert() else { return }
            let loaded = urls.compactMap { try? TrayDrop.DropItem(url: $0) }
            guard !loaded.isEmpty else { return }
            DispatchQueue.main.async {
                guard let index = self.baskets.firstIndex(where: { $0.id == basketID }) else { return }
                loaded.reversed().forEach { self.baskets[index].items.insert($0, at: 0) }
            }
        }
    }

    func remove(_ item: TrayDrop.DropItem, from basketID: UUID) {
        guard let index = baskets.firstIndex(where: { $0.id == basketID }) else { return }
        baskets[index].items.removeAll { $0.id == item.id }
    }

    func clear(basketID: UUID) {
        guard let index = baskets.firstIndex(where: { $0.id == basketID }) else { return }
        baskets[index].items.removeAll()
        if Defaults[.basketDismissesWhenEmptied] {
            close(basketID: basketID)
        }
    }

    /// Moves whatever the tray is holding into the notch Shelf.
    func sendToShelf(basketID: UUID) {
        guard let basket = baskets.first(where: { $0.id == basketID }) else { return }
        let items = basket.items
        DispatchQueue.main.async {
            items.reversed().forEach { TrayDrop.shared.items.updateOrInsert($0, at: 0) }
        }
        guard let index = baskets.firstIndex(where: { $0.id == basketID }) else { return }
        baskets[index].items.removeAll()
        close(basketID: basketID)
    }

    // MARK: Drag handling

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard Defaults[.enableBasket] else { return }
            let now = ProcessInfo.processInfo.systemUptime

            if !isDragging {
                isDragging = true
                resetShakeState()
                if Defaults[.basketRevealMode] == .instant {
                    reveal(at: NSEvent.mouseLocation)
                }
            }

            if Defaults[.basketRevealMode] == .shake {
                processShake(at: NSEvent.mouseLocation, time: now)
            }

        default:
            isDragging = false
            resetShakeState()
        }
    }

    private func resetShakeState() {
        lastDragX = nil
        lastDirection = 0
        travelSinceFlip = 0
        reversals = 0
        lastFlipTime = 0
    }

    /// Counts horizontal direction reversals inside a short window. Walking the
    /// pointer back and forth a few times is a deliberate signal; normal dragging
    /// rarely reverses this often.
    private func processShake(at point: CGPoint, time: TimeInterval) {
        guard let previousX = lastDragX else {
            lastDragX = point.x
            return
        }

        let dx = point.x - previousX
        lastDragX = point.x

        let sensitivity = Defaults[.basketShakeSensitivity]
        guard abs(dx) >= 0.5 else { return }

        let direction = dx > 0 ? 1 : -1

        if direction == lastDirection {
            travelSinceFlip += abs(dx)
        } else {
            if travelSinceFlip >= sensitivity.minimumTravel {
                reversals += 1
                lastFlipTime = time
            }
            lastDirection = direction
            travelSinceFlip = abs(dx)
        }

        if time - lastFlipTime > Self.shakeWindow {
            reversals = 0
        }

        if reversals >= sensitivity.reversalsRequired {
            resetShakeState()
            reveal(at: point)
        }
    }

    // MARK: Panels

    private func createPanel(for id: UUID) {
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: BasketView(basketID: id))

        panels[id] = panel
        panel.orderFrontRegardless()
    }

    private func positionPanel(for id: UUID, at point: CGPoint) {
        guard let panel = panels[id] else { return }

        let size = panel.frame.size
        var origin = CGPoint(x: point.x + 14, y: point.y - size.height - 14)

        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        panel.setFrameOrigin(origin)
    }

    private func feedback() {
        guard Defaults[.enableHaptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

#endif
