import SwiftUI

extension View {
    /// Blättert per Wischgeste entlang `axis`.
    /// `action` erhält `+1` (vor) oder `-1` (zurück).
    ///
    /// - macOS: Zwei-Finger-Wischen auf dem Trackpad / der Magic Mouse sowie das Mausrad.
    /// - iOS/visionOS: Wischen mit dem Finger.
    func onSwipeToPage(axis: Axis, perform action: @escaping (Int) -> Void) -> some View {
        #if os(macOS)
        background(ScrollSwipeCatcher(axis: axis, action: action))
        #else
        simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let primary = axis == .horizontal ? value.translation.width : value.translation.height
                    let cross = axis == .horizontal ? value.translation.height : value.translation.width
                    guard abs(primary) > 60, abs(primary) > abs(cross) else { return }
                    action(primary < 0 ? 1 : -1)
                }
        )
        #endif
    }
}

#if os(macOS)
import AppKit

private struct ScrollSwipeCatcher: NSViewRepresentable {
    let axis: Axis
    let action: (Int) -> Void

    func makeNSView(context: Context) -> ScrollSwipeView {
        let view = ScrollSwipeView()
        view.axis = axis
        view.action = action
        return view
    }

    func updateNSView(_ view: ScrollSwipeView, context: Context) {
        view.axis = axis
        view.action = action
    }
}

/// Unsichtbare Hilfs-View, die Scroll-Events über ihrem Bereich auswertet.
/// Pro Geste wird höchstens einmal geblättert; Mausrad-Rasten werden gedrosselt.
private final class ScrollSwipeView: NSView {
    var axis: Axis = .horizontal
    var action: ((Int) -> Void)?

    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var didTriggerInGesture = false
    private var lastWheelTrigger = Date.distantPast

    private let trackpadThreshold: CGFloat = 50
    private let wheelInterval: TimeInterval = 0.25

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    // Klicks und Taps an die SwiftUI-Views darüber durchreichen.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Gibt `true` zurück, wenn das Event verbraucht wurde.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil))
        else { return false }

        let primary = axis == .horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        let cross = axis == .horizontal ? event.scrollingDeltaY : event.scrollingDeltaX

        // Nachlaufender Schwung nach einer Trackpad-Geste.
        if !event.momentumPhase.isEmpty {
            return didTriggerInGesture
        }

        // Klassisches Mausrad: jede Raste blättert, gedrosselt.
        if !event.hasPreciseScrollingDeltas {
            guard primary != 0, abs(primary) >= abs(cross) else { return false }
            if Date.now.timeIntervalSince(lastWheelTrigger) > wheelInterval {
                lastWheelTrigger = .now
                action?(primary < 0 ? 1 : -1)
            }
            return true
        }

        // Trackpad / Magic Mouse: Bewegung einer Geste aufsummieren.
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            accumulated = 0
            didTriggerInGesture = false
        }

        let isOnAxis = abs(primary) > abs(cross)
        if !didTriggerInGesture, isOnAxis {
            accumulated += primary
            if abs(accumulated) > trackpadThreshold {
                didTriggerInGesture = true
                action?(accumulated < 0 ? 1 : -1)
            }
        }

        let consumed = didTriggerInGesture || isOnAxis
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            accumulated = 0
        }
        return consumed
    }
}
#endif
