import AppKit
import SwiftUI

struct PointerDragScrollBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.anchorView = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: NSView?

        private var eventMonitor: Any?
        private var dragStartLocation: NSPoint?
        private var dragStartOriginY: CGFloat = 0
        private var dragAxis = PointerDragAxis.pending

        func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            resetDrag()
        }

        private func handle(_ event: NSEvent) {
            guard let anchorView,
                  let scrollView = anchorView.enclosingScrollView,
                  event.window === scrollView.window
            else {
                resetDrag()
                return
            }

            switch event.type {
            case .leftMouseDown:
                guard isInsideViewport(event, scrollView: scrollView) else {
                    resetDrag()
                    return
                }
                dragStartLocation = event.locationInWindow
                dragStartOriginY = scrollView.contentView.bounds.origin.y
                dragAxis = .pending

            case .leftMouseDragged:
                guard let dragStartLocation else { return }
                let translationX = event.locationInWindow.x - dragStartLocation.x
                let translationY = event.locationInWindow.y - dragStartLocation.y

                if dragAxis == .pending {
                    dragAxis = PointerDragScrollMath.axis(
                        translationX: translationX,
                        translationY: translationY
                    )
                }
                guard dragAxis == .vertical,
                      let documentView = scrollView.documentView
                else {
                    return
                }

                let clipView = scrollView.contentView
                let minimumY = documentView.frame.minY
                let maximumY = max(minimumY, documentView.frame.maxY - clipView.bounds.height)
                let originY = PointerDragScrollMath.originY(
                    startOriginY: dragStartOriginY,
                    translationY: translationY,
                    minimumY: minimumY,
                    maximumY: maximumY
                )
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: originY))
                scrollView.reflectScrolledClipView(clipView)

            case .leftMouseUp:
                resetDrag()

            default:
                break
            }
        }

        private func isInsideViewport(_ event: NSEvent, scrollView: NSScrollView) -> Bool {
            let clipView = scrollView.contentView
            let location = clipView.convert(event.locationInWindow, from: nil)
            return clipView.bounds.contains(location)
        }

        private func resetDrag() {
            dragStartLocation = nil
            dragAxis = .pending
        }
    }
}

enum PointerDragAxis: Equatable {
    case pending
    case horizontal
    case vertical
}

enum PointerDragScrollMath {
    static func axis(
        translationX: CGFloat,
        translationY: CGFloat,
        minimumDistance: CGFloat = 4
    ) -> PointerDragAxis {
        guard max(abs(translationX), abs(translationY)) >= minimumDistance else { return .pending }
        return abs(translationY) > abs(translationX) ? .vertical : .horizontal
    }

    static func originY(
        startOriginY: CGFloat,
        translationY: CGFloat,
        minimumY: CGFloat,
        maximumY: CGFloat
    ) -> CGFloat {
        // NSEvent window coordinates grow upward: an upward pointer drag has a
        // positive translation and should reveal content farther down the feed.
        min(max(startOriginY + translationY, minimumY), maximumY)
    }
}
