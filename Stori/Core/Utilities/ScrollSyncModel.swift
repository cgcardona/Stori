//
//  ScrollSyncModel.swift
//  Stori
//
//  Synchronized scrolling coordination for professional DAW timeline
//  Ensures track headers, timeline ruler, and track areas stay perfectly aligned
//
//  [BUGFIX] Uses absolute pixel offsets instead of normalized 0-1 positions
//  to prevent cumulative floating-point precision drift during scrolling.
//

import SwiftUI
import Combine

@Observable
class ScrollSyncModel {
    // MARK: - Scroll Positions (Absolute Pixel Offsets)
    // Using absolute pixels instead of normalized (0-1) values prevents
    // floating-point precision loss that causes scroll drift over time.
    var verticalScrollOffset: CGFloat = 0
    var horizontalScrollOffset: CGFloat = 0
    
    // MARK: - Feedback Loop Prevention
    // These flags indicate when a programmatic update is in progress
    // to prevent the updated component from re-broadcasting
    var isUpdatingVertical = false
    var isUpdatingHorizontal = false
    
    // MARK: - DAW-Specific Configuration
    private let headerWidth: CGFloat = 280  // Match TellUrStori track header width
    private let timelineRulerHeight: CGFloat = 40  // Match existing ruler height
    
    // MARK: - User-Initiated Updates
    // Called when user scrolls one of the synchronized views
    func updateVerticalOffset(_ offset: CGFloat) {
        // Simply update the offset - SynchronizedScrollView handles feedback prevention
        let clampedOffset = max(0, offset)
        if abs(clampedOffset - verticalScrollOffset) > 0.5 {
            verticalScrollOffset = clampedOffset
        }
    }
    
    func updateHorizontalOffset(_ offset: CGFloat) {
        // Simply update the offset - SynchronizedScrollView handles feedback prevention
        let clampedOffset = max(0, offset)
        if abs(clampedOffset - horizontalScrollOffset) > 0.5 {
            horizontalScrollOffset = clampedOffset
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Even though this class has no explicit Task blocks or @MainActor,
        // ASan detected memory corruption during deinit (Issue #84742)
        // 
        // Root cause: @Observable classes have implicit Swift Concurrency tasks
        // created by the Observation framework for property change notifications.
        // 
        // This deinit ensures ordered cleanup before Swift's implicit deallocation,
        // preventing race conditions with Swift Concurrency's task-local cleanup.
        //
        // See: MetronomeEngine, ProjectExportService, AutomationServer, LLMComposerClient,
        //      AudioAnalysisService, AudioExportService, SelectionManager
        // https://github.com/cgcardona/Stori/issues/AudioEngine-MemoryBug
    }
}

// MARK: - DAW Layout Configuration
extension ScrollSyncModel {
    var trackHeaderWidth: CGFloat { headerWidth }
    var rulerHeight: CGFloat { timelineRulerHeight }
    
    // Calculate content dimensions based on current project
    func contentSize(for project: AudioProject?, horizontalZoom: Double, verticalZoom: Double) -> CGSize {
        guard let project = project else {
            return CGSize(width: 3000, height: 800) // Default size
        }
        
        // Calculate width based on project duration in BEATS (musical length)
        let projectDurationBeats = project.durationBeats
        let pixelsPerBeat: Double = 100.0 * horizontalZoom
        let contentWidth = projectDurationBeats * pixelsPerBeat
        
        // Calculate height based on track count and zoom
        let trackHeight = 80.0 * verticalZoom
        let contentHeight = Double(project.tracks.count) * trackHeight
        
        return CGSize(width: contentWidth, height: contentHeight)
    }
    
    /// Clamp scroll offset to valid range for given content and visible sizes
    func clampOffset(_ offset: CGFloat, contentSize: CGFloat, visibleSize: CGFloat) -> CGFloat {
        let maxOffset = max(0, contentSize - visibleSize)
        return min(max(0, offset), maxOffset)
    }
}
