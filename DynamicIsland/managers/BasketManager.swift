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

/// How a floating basket is summoned.
///
/// `shortcut` deliberately does not respond to dragging at all -- some people
/// want the tray out of the way until they ask for it.
enum BasketRevealMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case shake
    case instant
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shake: return String(localized: "Shake while dragging")
        case .instant: return String(localized: "As soon as a drag starts")
        case .shortcut: return String(localized: "Only from the shortcut")
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
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very high")
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
    /// Moves the tray with the pointer while a file is being dragged.
    ///
    /// Off by default, and deliberately so: a tray that chases the pointer can
    /// never be dropped onto, because it is always moving away from the file being
    /// carried. On, it keeps the tray beside the cursor for someone who only ever
    /// finishes a drag into it the moment it appears.
    static let basketFollowsCursor = Key<Bool>("basketFollowsCursor", default: false)
    /// Seconds between the reveal trigger and the tray appearing. Non-zero keeps
    /// an accidental shake from flashing a tray on screen.
    static let basketAppearDelay = Key<Double>("basketAppearDelay", default: 0)
    /// Seconds an empty tray waits after a drag ends before it closes itself.
    /// Zero leaves it on screen until it is closed by hand.
    static let basketHideDelay = Key<Double>("basketHideDelay", default: 3)
}

// MARK: - Model

/// One floating tray. Items are held with the same value type the Shelf uses so a
/// basket can hand a pile straight to the tray without converting anything.
struct Basket: Identifiable {
    let id: UUID
    var items: [TrayDrop.DropItem]
}

// MARK: - Shake detection

/// Counts horizontal direction reversals inside a short window. Walking the
/// pointer back and forth a few times is a deliberate signal; normal dragging
/// rarely reverses this often.
///
/// This is the only part of the tray's reveal logic that is not event plumbing,
/// so it is kept as plain value logic that can be driven from a test instead of
/// from a real mouse.
struct BasketShakeTracker {
    /// Minimum horizontal travel, in points, before a swing counts.
    static let minimumStep: CGFloat = 0.5

    private var lastX: CGFloat?
    private var lastDirection: Int = 0
    private var travelSinceFlip: CGFloat = 0
    private var reversals = 0
    private var lastFlipTime: TimeInterval = 0

    mutating func reset() {
        lastX = nil
        lastDirection = 0
        travelSinceFlip = 0
        reversals = 0
        lastFlipTime = 0
    }

    /// Feeds one pointer position in, and answers whether a deliberate shake has
    /// just completed. Resets itself when it has, so the caller does not have to.
    mutating func register(
        x: CGFloat,
        at time: TimeInterval,
        sensitivity: BasketShakeSensitivity,
        window: TimeInterval = 0.6
    ) -> Bool {
        guard let previousX = lastX else {
            lastX = x
            return false
        }

        lastX = x
        let dx = x - previousX
        guard abs(dx) >= Self.minimumStep else { return false }

        // A pause between swings ends the streak before this swing is counted, so
        // a few slow wiggles spread over several seconds never add up to a shake.
        if time - lastFlipTime > window {
            reversals = 0
        }

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

        guard reversals >= sensitivity.reversalsRequired else { return false }
        reset()
        return true
    }
}

// MARK: - Dismissal

/// Decides when an empty tray may be tidied away at the end of a drag.
///
/// The rule that matters: a tray summoned *by* a drag belongs to that drag. It was
/// just asked for, and the file that summoned it is about to be dropped — closing
/// it the moment the mouse comes up, before anything can be put in it, is what made
/// the tray feel like it was vanishing on its own. A tray that predates the drag is
/// stale, and the end of a drag is a good moment to clear it.
///
/// Kept as plain value logic so the timing rules can be driven from a test rather
/// than from a real mouse, the same way `BasketShakeTracker` is.
struct BasketEmptyClosePolicy {
    private var summonedSinceLastTidy = false

    /// A tray was just put on screen.
    mutating func noteSummon() {
        summonedSinceLastTidy = true
    }

    /// A drag has ended. Answers whether empty trays may now be closed.
    mutating func shouldTidyEmptyTraysAfterDrag() -> Bool {
        guard summonedSinceLastTidy else { return true }
        // One drag of grace: the summon is spent here, so the next drag that ends
        // with the tray still empty does tidy it away.
        summonedSinceLastTidy = false
        return false
    }

}

// MARK: - Manager

/// Presents floating trays next to the pointer. A tray is revealed by shaking the
/// pointer during a drag (or immediately, depending on preference) so a
/// half-finished pile of files has somewhere to wait that is not the top of the
/// screen.
final class BasketManager: ObservableObject {
    static let shared = BasketManager()

    @Published private(set) var baskets: [Basket] = []
    /// The tray the shortcut, the switcher and outside-click tidying treat as
    /// "the" basket.
    @Published private(set) var activeBasketID: UUID?

    private var panels: [UUID: NSPanel] = [:]
    private var monitors: [Any] = []

    // Drag + shake tracking. All of this is main-thread only, because NSEvent
    // monitors deliver on the main run loop.
    private var isDragging = false
    private var shakeTracker = BasketShakeTracker()
    private var lastRevealTime: TimeInterval = 0
    private var lastFollowTime: TimeInterval = 0

    private var revealWork: DispatchWorkItem?
    private var emptyCloseWork: DispatchWorkItem?
    private var outsideCloseWork: DispatchWorkItem?
    private var emptyClosePolicy = BasketEmptyClosePolicy()

    private static let shakeWindow: TimeInterval = 0.6
    private static let revealCooldown: TimeInterval = 0.7
    /// How long a click outside is given to turn into a drag before it is treated
    /// as a plain click. Picking a file up is a click *and* a drag, and the tray
    /// must not be dismissed by the click half of that.
    private static let clickGrace: TimeInterval = 0.45
    private static let followInterval: TimeInterval = 1.0 / 60.0
    static let panelSize = CGSize(width: 248, height: 276)

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard monitors.isEmpty else { return }

        let dragMask: NSEvent.EventTypeMask = [
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseUp, .rightMouseUp,
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: dragMask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: dragMask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }

        // Clicking anywhere outside the trays tidies away the empty ones. A tray
        // holding files is left alone: closing it would throw the pile away, and
        // it is still there waiting to be used.
        if let outsideClicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                // `NSEvent.mouseLocation` is the reliable screen coordinate for a
                // global monitor; the window-relative one is not usable here.
                self?.handleOutsideClick(at: NSEvent.mouseLocation)
            }
        ) {
            monitors.append(outsideClicks)
        }

        // Local monitors only see keys once a Vone panel is key, which is why the
        // trays take key focus when they appear.
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, let self, !self.baskets.isEmpty else { return event }
            self.dismissFrontmostBasket()
            return nil
        }) {
            monitors.append(escape)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        revealWork?.cancel()
        emptyCloseWork?.cancel()
        closeAll()
    }

    // MARK: Presentation

    /// Reveals a tray next to `screenPoint` (AppKit screen coordinates), after the
    /// configured appear delay.
    func reveal(at screenPoint: CGPoint) {
        revealWork?.cancel()

        let delay = max(0, Defaults[.basketAppearDelay])
        guard delay > 0 else {
            performReveal(at: screenPoint)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performReveal(at: screenPoint)
        }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performReveal(at screenPoint: CGPoint) {
        guard Defaults[.enableBasket] else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRevealTime > Self.revealCooldown else { return }
        lastRevealTime = now

        emptyCloseWork?.cancel()
        emptyClosePolicy.noteSummon()

        if !Defaults[.basketAllowsMultiple], let existing = baskets.first {
            positionPanel(for: existing.id, at: screenPoint)
            activate(basketID: existing.id)
            return
        }

        let basket = Basket(id: UUID(), items: [])
        baskets.append(basket)
        createPanel(for: basket.id)
        positionPanel(for: basket.id, at: screenPoint)
        activate(basketID: basket.id)
    }

    /// Shows a tray at the pointer, or closes the front one when a tray is
    /// already open. This is what the keyboard shortcut does, and it is also the
    /// only way to summon a tray while `BasketRevealMode.shortcut` is selected.
    func toggle() {
        if baskets.isEmpty {
            reveal(at: NSEvent.mouseLocation)
        } else {
            dismissFrontmostBasket()
        }
    }

    /// Brings a tray to the front and makes it the one the keyboard acts on.
    func activate(basketID: UUID) {
        guard let panel = panels[basketID] else { return }
        activeBasketID = basketID
        panel.makeKeyAndOrderFront(nil)
        feedback()
    }

    func close(basketID: UUID) {
        panels[basketID]?.orderOut(nil)
        panels[basketID] = nil
        baskets.removeAll { $0.id == basketID }

        if activeBasketID == basketID {
            activeBasketID = baskets.last?.id
        }
    }

    func closeAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        baskets.removeAll()
        activeBasketID = nil
    }

    /// Closes the frontmost tray, which is what Escape does.
    private func dismissFrontmostBasket() {
        guard let id = activeBasketID ?? baskets.first?.id else { return }
        close(basketID: id)
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
                self.emptyCloseWork?.cancel()
            }
        }
    }

    func remove(_ item: TrayDrop.DropItem, from basketID: UUID) {
        guard let index = baskets.firstIndex(where: { $0.id == basketID }) else { return }
        baskets[index].items.removeAll { $0.id == item.id }

        if baskets[index].items.isEmpty, Defaults[.basketDismissesWhenEmptied] {
            close(basketID: basketID)
        }
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
        guard !items.isEmpty else { return }

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
                emptyCloseWork?.cancel()
                // The click that started this drag is not a click on the desktop:
                // it is the user picking a file up, quite possibly to put in the
                // tray they summoned a moment ago.
                outsideCloseWork?.cancel()

                if Defaults[.basketRevealMode] == .instant {
                    reveal(at: NSEvent.mouseLocation)
                }
            }

            if Defaults[.basketRevealMode] == .shake {
                processShake(at: NSEvent.mouseLocation, time: now)
            }

            followPointerIfNeeded(at: NSEvent.mouseLocation, time: now)

        default:
            isDragging = false
            resetShakeState()
            // A shake that starts a reveal but releases before the appear delay
            // elapses should not leave a tray behind.
            revealWork?.cancel()
            if emptyClosePolicy.shouldTidyEmptyTraysAfterDrag() {
                scheduleEmptyBasketClose()
            }
        }
    }

    private func resetShakeState() {
        shakeTracker.reset()
    }

    private func processShake(at point: CGPoint, time: TimeInterval) {
        let shaken = shakeTracker.register(
            x: point.x,
            at: time,
            sensitivity: Defaults[.basketShakeSensitivity],
            window: Self.shakeWindow
        )
        if shaken {
            reveal(at: point)
        }
    }

    /// Keeps a lone tray under the pointer. With several trays on screen the
    /// pointer cannot mean all of them, so they are left where they were placed.
    private func followPointerIfNeeded(at point: CGPoint, time: TimeInterval) {
        guard Defaults[.basketFollowsCursor], baskets.count == 1 else { return }
        guard time - lastFollowTime > Self.followInterval else { return }
        lastFollowTime = time
        positionPanel(for: baskets[0].id, at: point)
    }

    /// Tidies away trays that are still empty once a drag has finished, so a
    /// reveal that missed does not leave an empty panel on screen.
    ///
    /// A tray the pointer is resting in is left alone: the pointer being in it is
    /// the user about to use it, and closing a panel out from under the cursor is
    /// the other half of "it disappears on its own".
    private func scheduleEmptyBasketClose() {
        let delay = Defaults[.basketHideDelay]
        guard delay > 0 else { return }

        emptyCloseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pointer = NSEvent.mouseLocation
            for basket in self.baskets where basket.items.isEmpty {
                if let frame = self.panels[basket.id]?.frame, frame.contains(pointer) { continue }
                self.close(basketID: basket.id)
            }
        }
        emptyCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// A click outside an empty tray closes it — but only once the click is known
    /// not to be the start of a drag, because picking a file up is a click too.
    private func handleOutsideClick(at point: CGPoint) {
        outsideCloseWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for basket in self.baskets where basket.items.isEmpty {
                guard let frame = self.panels[basket.id]?.frame else { continue }
                if frame.contains(point) { continue }
                self.close(basketID: basket.id)
            }
        }
        outsideCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickGrace, execute: work)
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
        // .screenSaver matches the clipboard panel: a tray that is already on
        // screen when a full-screen app is in front still needs to be reachable.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
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
