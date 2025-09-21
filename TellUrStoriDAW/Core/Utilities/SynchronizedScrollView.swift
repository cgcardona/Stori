//
//  SynchronizedScrollView.swift
//  TellUrStoriDAW
//
//  AppKit NSScrollView bridge for pixel-perfect synchronized scrolling
//  Enables professional DAW-style scroll coordination between timeline components
//

import SwiftUI
import AppKit

struct SynchronizedScrollView<Content: View>: NSViewRepresentable {
    // MARK: - Configuration
    enum ScrollAxis { 
        case horizontal, vertical, both 
    }
    
    let axes: ScrollAxis
    let showsIndicators: Bool
    let contentSize: CGSize
    
    // MARK: - Bindings
    @Binding var normalizedX: CGFloat   // 0.0 to 1.0
    @Binding var normalizedY: CGFloat   // 0.0 to 1.0
    
    // MARK: - Feedback Prevention
    let isUpdatingX: () -> Bool
    let isUpdatingY: () -> Bool
    let onUserScrollX: (CGFloat) -> Void
    let onUserScrollY: (CGFloat) -> Void
    
    // MARK: - Content
    @ViewBuilder var content: () -> Content
    
    // MARK: - Coordinator
    final class Coordinator: NSObject {
        var parent: SynchronizedScrollView
        var boundsObserver: NSObjectProtocol?
        
        // Prevent feedback during programmatic updates
        var ignoringUserScrollX = false
        var ignoringUserScrollY = false
        
        init(_ parent: SynchronizedScrollView) {
            self.parent = parent
        }
        
        deinit {
            if let observer = boundsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        @objc func clipViewBoundsChanged(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let documentView = clipView.documentView else { return }
            
            let maxScrollX = max(0, documentView.bounds.width - clipView.bounds.width)
            let maxScrollY = max(0, documentView.bounds.height - clipView.bounds.height)
            let currentX = clipView.bounds.origin.x
            let currentY = clipView.bounds.origin.y
            
            // Update horizontal position if user scrolled and we're not updating programmatically
            if maxScrollX > 0 && !ignoringUserScrollX && !parent.isUpdatingX() {
                let normalizedX = min(max(currentX / maxScrollX, 0), 1)
                parent.onUserScrollX(normalizedX)
            }
            
            // Update vertical position if user scrolled and we're not updating programmatically
            if maxScrollY > 0 && !ignoringUserScrollY && !parent.isUpdatingY() {
                let normalizedY = min(max(currentY / maxScrollY, 0), 1)
                parent.onUserScrollY(normalizedY)
            }
        }
        
        func applyProgrammaticScroll(normalizedX: CGFloat, normalizedY: CGFloat, to scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            guard let documentView = clipView.documentView else { return }
            
            let maxScrollX = max(0, documentView.bounds.width - clipView.bounds.width)
            let maxScrollY = max(0, documentView.bounds.height - clipView.bounds.height)
            
            var newOrigin = clipView.bounds.origin
            
            // Apply horizontal scroll if this view supports it
            if maxScrollX > 0 && (parent.axes == .horizontal || parent.axes == .both) {
                ignoringUserScrollX = true
                newOrigin.x = normalizedX * maxScrollX
            }
            
            // Apply vertical scroll if this view supports it
            if maxScrollY > 0 && (parent.axes == .vertical || parent.axes == .both) {
                ignoringUserScrollY = true
                newOrigin.y = normalizedY * maxScrollY
            }
            
            // Apply scroll without animation to prevent rubber-band effects
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                clipView.setBoundsOrigin(newOrigin)
                scrollView.reflectScrolledClipView(clipView)
            }, completionHandler: {
                // Re-enable user scroll detection on next run loop
                DispatchQueue.main.async {
                    self.ignoringUserScrollX = false
                    self.ignoringUserScrollY = false
                }
            })
        }
    }
    
    // MARK: - NSViewRepresentable Implementation
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        
        // Configure scroll view appearance
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = (axes != .vertical) && showsIndicators
        scrollView.hasVerticalScroller = (axes != .horizontal) && showsIndicators
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .legacy  // Consistent with DAW aesthetics
        
        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView:
            content()
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .clipped()
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set up document view
        scrollView.documentView = hostingView
        scrollView.contentView.postsBoundsChangedNotifications = true
        
        // Observe bounds changes for scroll synchronization
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] notification in
            coordinator?.clipViewBoundsChanged(notification)
        }
        
        // Apply initial scroll position
        context.coordinator.applyProgrammaticScroll(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            to: scrollView
        )
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Apply programmatic scroll updates from the sync model
        context.coordinator.applyProgrammaticScroll(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            to: scrollView
        )
        
        // Update content size if needed (for dynamic project changes)
        if scrollView.documentView is NSHostingView<AnyView> {
            // Content size updates would go here if needed
        }
    }
}

// MARK: - Convenience Initializers for DAW Components
extension SynchronizedScrollView {
    // Track headers (vertical scrolling only)
    static func trackHeaders<T: View>(
        contentSize: CGSize,
        normalizedY: Binding<CGFloat>,
        isUpdatingY: @escaping () -> Bool,
        onUserScrollY: @escaping (CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> T
    ) -> SynchronizedScrollView<T> {
        SynchronizedScrollView<T>(
            axes: .vertical,
            showsIndicators: true,
            contentSize: contentSize,
            normalizedX: .constant(0),
            normalizedY: normalizedY,
            isUpdatingX: { false },
            isUpdatingY: isUpdatingY,
            onUserScrollX: { _ in },
            onUserScrollY: onUserScrollY,
            content: content
        )
    }
    
    // Timeline ruler (horizontal scrolling only)
    static func timelineRuler<T: View>(
        contentSize: CGSize,
        normalizedX: Binding<CGFloat>,
        isUpdatingX: @escaping () -> Bool,
        onUserScrollX: @escaping (CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> T
    ) -> SynchronizedScrollView<T> {
        SynchronizedScrollView<T>(
            axes: .horizontal,
            showsIndicators: true,
            contentSize: contentSize,
            normalizedX: normalizedX,
            normalizedY: .constant(0),
            isUpdatingX: isUpdatingX,
            isUpdatingY: { false },
            onUserScrollX: onUserScrollX,
            onUserScrollY: { _ in },
            content: content
        )
    }
    
    // Tracks area (both axes - master scroll view)
    static func tracksArea<T: View>(
        contentSize: CGSize,
        normalizedX: Binding<CGFloat>,
        normalizedY: Binding<CGFloat>,
        isUpdatingX: @escaping () -> Bool,
        isUpdatingY: @escaping () -> Bool,
        onUserScrollX: @escaping (CGFloat) -> Void,
        onUserScrollY: @escaping (CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> T
    ) -> SynchronizedScrollView<T> {
        SynchronizedScrollView<T>(
            axes: .both,
            showsIndicators: true,
            contentSize: contentSize,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            isUpdatingX: isUpdatingX,
            isUpdatingY: isUpdatingY,
            onUserScrollX: onUserScrollX,
            onUserScrollY: onUserScrollY,
            content: content
        )
    }
}
