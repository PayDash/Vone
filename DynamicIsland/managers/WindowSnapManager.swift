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
import ApplicationServices
import Defaults
import OSLog

extension Defaults.Keys {
    static let enableWindowSnap = Key<Bool>("enableWindowSnap", default: true)
}

enum SnapPosition: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: return String(localized: "Left half")
        case .rightHalf: return String(localized: "Right half")
        case .topHalf: return String(localized: "Top half")
        case .bottomHalf: return String(localized: "Bottom half")
        case .topLeft: return String(localized: "Top left")
        case .topRight: return String(localized: "Top right")
        case .bottomLeft: return String(localized: "Bottom left")
        case .bottomRight: return String(localized: "Bottom right")
        case .maximize: return String(localized: "Maximise")
        case .center: return String(localized: "Centre")
        }
    }
}

/// Moves and resizes the focused window of the frontmost app through the
/// Accessibility API. Vone already asks for Accessibility, so this needs no new
/// permission.
enum WindowSnapManager {
    private static let log = os.Logger(subsystem: "com.ebullioscopic.Atoll", category: "WindowSnap")
    nonisolated(unsafe) private static var didAskForPermission = false

    static func snap(_ position: SnapPosition) {
        guard Defaults[.enableWindowSnap] else { return }
        guard AXIsProcessTrusted() else {
            log.error("Accessibility permission is required to move windows; prompting.")
            requestAccessibilityPermission()
            return
        }
        guard let window = focusedWindow() else {
            log.debug("No focused window to snap.")
            return
        }
        guard let screen = screenContaining(window: window) ?? NSScreen.main else { return }

        let target = targetFrame(position, in: screen.visibleFrame)
        apply(target, to: window)
    }

    /// Puts up the system's Accessibility prompt. A shortcut fired from an app
    /// that has never been granted the permission would otherwise do nothing at
    /// all with no way to tell why; the Tools settings page carries the standing
    /// explanation and the button that opens Privacy & Security.
    private static func requestAccessibilityPermission() {
        guard !didAskForPermission else { return }
        didAskForPermission = true

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    // MARK: Accessibility

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value
        else { return nil }

        // AXUIElement is a CFType; the unchecked cast is the documented pattern here.
        return (window as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return convertToCocoa(CGRect(origin: origin, size: size))
    }

    private static func screenContaining(window: AXUIElement) -> NSScreen? {
        guard let rect = frame(of: window) else { return nil }
        return NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
    }

    private static func apply(_ cocoaRect: NSRect, to window: AXUIElement) {
        let axRect = convertToAX(cocoaRect)

        var origin = axRect.origin
        var size = axRect.size

        // Size first, then position: some apps clamp the origin while resizing.
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let positionValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: Geometry

    /// The frame a window takes for `position` inside `visible`. Pure arithmetic,
    /// and the one part of snapping that can be checked without a mouse or a
    /// second app, so it is kept free of the Accessibility plumbing.
    static func targetFrame(_ position: SnapPosition, in visible: NSRect) -> NSRect {
        let midX = visible.minX + visible.width / 2
        let midY = visible.minY + visible.height / 2
        let halfW = visible.width / 2
        let halfH = visible.height / 2

        switch position {
        case .leftHalf:
            return NSRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height)
        case .rightHalf:
            return NSRect(x: midX, y: visible.minY, width: halfW, height: visible.height)
        case .topHalf:
            return NSRect(x: visible.minX, y: midY, width: visible.width, height: halfH)
        case .bottomHalf:
            return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfH)
        case .topLeft:
            return NSRect(x: visible.minX, y: midY, width: halfW, height: halfH)
        case .topRight:
            return NSRect(x: midX, y: midY, width: halfW, height: halfH)
        case .bottomLeft:
            return NSRect(x: visible.minX, y: visible.minY, width: halfW, height: halfH)
        case .bottomRight:
            return NSRect(x: midX, y: visible.minY, width: halfW, height: halfH)
        case .maximize:
            return visible
        case .center:
            let width = min(visible.width * 0.7, visible.width)
            let height = min(visible.height * 0.7, visible.height)
            return NSRect(
                x: visible.minX + (visible.width - width) / 2,
                y: visible.minY + (visible.height - height) / 2,
                width: width,
                height: height
            )
        }
    }

    /// Accessibility uses a top-left origin measured from the primary display,
    /// while AppKit measures from the bottom-left. Both conversions go through the
    /// primary screen's height.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    static func convertToAX(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func convertToCocoa(_ rect: CGRect) -> NSRect {
        NSRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
#endif
