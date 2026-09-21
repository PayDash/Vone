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
import SwiftUI

// MARK: - Measurement

private struct ScrollableRowContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Wheel monitor

/// `scrollWheel` is not delivered to a plain `NSView` when SwiftUI layers sit
/// above it, so the row listens on the event stream instead -- and only acts
/// while the pointer is actually inside it, so it never steals a scroll meant
/// for something else.
private struct RowScrollMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: (CGFloat) -> Void
        private var monitor: Any?
        private var lastEventTimestamp: TimeInterval = 0

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard let delta = self.delta(for: event, in: view) else { return event }
                self.onScroll(delta)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            lastEventTimestamp = 0
        }

        private func delta(for event: NSEvent, in view: NSView) -> CGFloat? {
            guard lastEventTimestamp != event.timestamp else { return nil }
            lastEventTimestamp = event.timestamp
            guard isCursorInside(view) else { return nil }

            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY

            // A wheel reports whole lines where a trackpad reports points, so the
            // two have to be brought onto the same scale before they are used.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 18

            // Either axis drives the row: the gesture people reach for over a
            // horizontal strip is usually a vertical one.
            let raw = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
            let delta = raw * scale
            guard abs(delta) > 0.01 else { return nil }
            return delta
        }

        private func isCursorInside(_ view: NSView) -> Bool {
            guard let window = view.window else { return false }
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return view.bounds.contains(view.convert(windowPoint, from: nil))
        }
    }
}

// MARK: - Row

/// A single horizontal row that scrolls, and that looks like it can.
///
/// `ScrollView(.horizontal)` ignores a plain mouse wheel on macOS -- it follows a
/// trackpad's horizontal axis only -- which leaves a row inside a narrow floating
/// panel looking finished but dead: content parks past the right edge with no way
/// to reach it. This row moves its own offset from an `NSEvent` monitor, so a
/// wheel, a vertical trackpad swipe and a horizontal one all work, and it fades
/// its edges and draws a scrollbar whenever there is somewhere to go.
struct ScrollableRow<Content: View>: View {
    var spacing: CGFloat = 6
    var edgeFadeWidth: CGFloat = 16

    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var isScrollbarVisible = false
    @State private var scrollbarToken = 0

    private var travel: CGFloat { max(0, contentWidth - viewportWidth) }
    private var canScroll: Bool { travel > 0.5 }
    private var isAtStart: Bool { offset <= 0.5 }
    private var isAtEnd: Bool { offset >= travel - 0.5 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                row
                    .offset(x: -offset)

                if canScroll {
                    scrollbar(trackWidth: proxy.size.width)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
            .mask(edgeMask)
            .onAppear { viewportWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in
                viewportWidth = width
                clampOffset()
            }
        }
        .onPreferenceChange(ScrollableRowContentWidthKey.self) { width in
            contentWidth = width
            clampOffset()
        }
        .background(RowScrollMonitor(onScroll: scroll(by:)))
        .onHover { hovering in
            isHovering = hovering
            if hovering { isScrollbarVisible = true } else { scheduleScrollbarFade() }
        }
    }

    private var row: some View {
        HStack(spacing: spacing) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollableRowContentWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
    }

    // MARK: Affordance

    /// Fades whichever edge has content hiding behind it, so the row reads as
    /// scrollable before anyone tries to scroll it.
    private var edgeMask: LinearGradient {
        let fade: CGFloat = viewportWidth > 1
            ? min(edgeFadeWidth / viewportWidth, 0.4)
            : 0

        var stops: [Gradient.Stop] = []
        if canScroll, !isAtStart {
            stops.append(.init(color: .black.opacity(0), location: 0))
            stops.append(.init(color: .black, location: fade))
        } else {
            stops.append(.init(color: .black, location: 0))
        }

        if canScroll, !isAtEnd {
            stops.append(.init(color: .black, location: 1 - fade))
            stops.append(.init(color: .black.opacity(0), location: 1))
        } else {
            stops.append(.init(color: .black, location: 1))
        }

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func scrollbar(trackWidth: CGFloat) -> some View {
        let ratio = viewportWidth / max(contentWidth, 1)
        let thumbWidth = max(20, (trackWidth - 2) * ratio)
        let progress = travel > 0 ? offset / travel : 0
        let x = progress * max((trackWidth - 2) - thumbWidth, 0)

        return Capsule()
            .fill(Color.primary.opacity(0.3))
            .frame(width: thumbWidth, height: 3)
            .offset(x: x + 1, y: -1)
            .opacity(isScrollbarVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isScrollbarVisible)
            .allowsHitTesting(false)
    }

    private func scheduleScrollbarFade() {
        guard isScrollbarVisible else { return }
        scrollbarToken += 1
        let token = scrollbarToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard token == scrollbarToken, !isHovering else { return }
            isScrollbarVisible = false
        }
    }

    // MARK: Movement

    private func scroll(by delta: CGFloat) {
        guard travel > 0 else { return }
        offset = min(max(offset - delta, 0), travel)

        if !isScrollbarVisible { isScrollbarVisible = true }
        scheduleScrollbarFade()
    }

    private func clampOffset() {
        offset = min(max(offset, 0), travel)
    }
}
#endif
