//
//  SynchronizedScrollView.swift
//  Stori
//
//  AppKit NSScrollView bridge for pixel-perfect synchronized scrolling
//  Enables professional DAW-style scroll coordination between timeline components
//
//  [BUGFIX] Uses absolute pixel offsets instead of normalized 0-1 positions
//  to prevent cumulative floating-point precision drift during scrolling.
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
    
    // MARK: - Bindings (Absolute Pixel Offsets)
    // Using absolute pixels instead of normalized (0-1) values prevents
    // floating-point precision loss that causes scroll drift over time.
    @Binding var offsetX: CGFloat   // Absolute pixel offset
    @Binding var offsetY: CGFloat   // Absolute pixel offset
    
    // MARK: - Feedback Prevention
    let isUpdatingX: () -> Bool
    let isUpdatingY: () -> Bool
    let onUserScrollX: (CGFloat) -> Void
    let onUserScrollY: (CGFloat) -> Void
    
    // MARK: - Content
    @ViewBuilder var content: () -> Content
    
    // Wrapper to ensure consistent type for NSHostingView
    struct ContentWrapper<C: View>: View {
        let content: C
        let size: CGSize
        
        var body: some View {
            content
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
        }
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject {
        var parent: SynchronizedScrollView
        var boundsObserver: NSObjectProtocol?
        
        // Prevent feedback during programmatic updates
        var ignoringUserScrollX = false
        var ignoringUserScrollY = false
        
        // Track last applied position to avoid redundant updates (in pixels)
        var lastAppliedX: CGFloat = -1
        var lastAppliedY: CGFloat = -1
        
        // Threshold for considering positions equal (0.5 pixels - sub-pixel precision)
        private let positionThreshold: CGFloat = 0.5
        
        init(_ parent: SynchronizedScrollView) {
            self.parent = parent
        }
        
        deinit {
            // Synchronous cleanup of NotificationCenter observer.
            if let observer = boundsObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        @objc func clipViewBoundsChanged(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            
            let currentX = clipView.bounds.origin.x
            let currentY = clipView.bounds.origin.y
            
            // Update horizontal position if user scrolled and we're not updating programmatically
            if (parent.axes == .horizontal || parent.axes == .both) 
                && !ignoringUserScrollX && !parent.isUpdatingX() {
                // Only report if significantly different from last applied (0.5 pixel threshold)
                if abs(currentX - lastAppliedX) > positionThreshold {
                    lastAppliedX = currentX  // Update our tracking with exact pixel value
                    parent.onUserScrollX(currentX)
                }
            }
            
            // Update vertical position if user scrolled and we're not updating programmatically
            if (parent.axes == .vertical || parent.axes == .both)
                && !ignoringUserScrollY && !parent.isUpdatingY() {
                // Only report if significantly different from last applied
                if abs(currentY - lastAppliedY) > positionThreshold {
                    lastAppliedY = currentY  // Update our tracking with exact pixel value
                    parent.onUserScrollY(currentY)
                }
            }
        }
        
        func applyProgrammaticScroll(offsetX: CGFloat, offsetY: CGFloat, to scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            guard let documentView = clipView.documentView else { return }
            
            let maxScrollX = max(0, documentView.bounds.width - clipView.bounds.width)
            let maxScrollY = max(0, documentView.bounds.height - clipView.bounds.height)
            
            // Clamp offsets to valid range
            let clampedX = min(max(0, offsetX), maxScrollX)
            let clampedY = min(max(0, offsetY), maxScrollY)
            
            // Check if we actually need to update (avoid fighting with user scroll)
            let needsHorizontalUpdate = (parent.axes == .horizontal || parent.axes == .both) 
                && abs(clampedX - lastAppliedX) > positionThreshold
            
            let needsVerticalUpdate = (parent.axes == .vertical || parent.axes == .both)
                && abs(clampedY - lastAppliedY) > positionThreshold
            
            // If nothing changed, don't apply (this prevents fighting with user scroll)
            guard needsHorizontalUpdate || needsVerticalUpdate else { return }
            
            var newOrigin = clipView.bounds.origin
            
            // Apply horizontal scroll if needed
            if needsHorizontalUpdate {
                ignoringUserScrollX = true
                newOrigin.x = clampedX
                lastAppliedX = clampedX
            }
            
            // Apply vertical scroll if needed
            if needsVerticalUpdate {
                ignoringUserScrollY = true
                newOrigin.y = clampedY
                lastAppliedY = clampedY
            }
            
            // Apply scroll without animation to prevent rubber-band effects
            clipView.setBoundsOrigin(newOrigin)
            scrollView.reflectScrolledClipView(clipView)
            
            // Re-enable user scroll detection on next run loop
            DispatchQueue.main.async { [weak self] in
                self?.ignoringUserScrollX = false
                self?.ignoringUserScrollY = false
            }
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
        
        // Create hosting view for SwiftUI content using wrapper
        let hostingView = NSHostingView(rootView: ContentWrapper(content: content(), size: contentSize))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        
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
            offsetX: offsetX,
            offsetY: offsetY,
            to: scrollView
        )
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Update content size and root view
        if let hostingView = scrollView.documentView as? NSHostingView<ContentWrapper<Content>> {
            // Update the root view with new content and size
            hostingView.rootView = ContentWrapper(content: content(), size: contentSize)
            
            // Explicitly update frame if size changed
            if hostingView.frame.size != contentSize {
                hostingView.frame = CGRect(origin: .zero, size: contentSize)
            }
        }
        
        // Apply programmatic scroll updates from the sync model
        context.coordinator.applyProgrammaticScroll(
            offsetX: offsetX,
            offsetY: offsetY,
            to: scrollView
        )
    }
}

// MARK: - Convenience Initializers for DAW Components
extension SynchronizedScrollView {
    // Track headers (vertical scrolling only)
    static func trackHeaders<T: View>(
        contentSize: CGSize,
        offsetY: Binding<CGFloat>,
        isUpdatingY: @escaping () -> Bool,
        onUserScrollY: @escaping (CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> T
    ) -> SynchronizedScrollView<T> {
        SynchronizedScrollView<T>(
            axes: .vertical,
            showsIndicators: true,
            contentSize: contentSize,
            offsetX: .constant(0),
            offsetY: offsetY,
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
        offsetX: Binding<CGFloat>,
        isUpdatingX: @escaping () -> Bool,
        onUserScrollX: @escaping (CGFloat) -> Void,
        @ViewBuilder content: @escaping () -> T
    ) -> SynchronizedScrollView<T> {
        SynchronizedScrollView<T>(
            axes: .horizontal,
            showsIndicators: true,
            contentSize: contentSize,
            offsetX: offsetX,
            offsetY: .constant(0),
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
        offsetX: Binding<CGFloat>,
        offsetY: Binding<CGFloat>,
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
            offsetX: offsetX,
            offsetY: offsetY,
            isUpdatingX: isUpdatingX,
            isUpdatingY: isUpdatingY,
            onUserScrollX: onUserScrollX,
            onUserScrollY: onUserScrollY,
            content: content
        )
    }
}
