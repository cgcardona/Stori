//
//  ScrollSyncModel.swift
//  TellUrStoriDAW
//
//  Synchronized scrolling coordination for professional DAW timeline
//  Ensures track headers, timeline ruler, and track areas stay perfectly aligned
//

import SwiftUI
import Combine

@Observable
class ScrollSyncModel {
    // MARK: - Scroll Positions (Normalized 0.0 to 1.0)
    var verticalScrollPosition: CGFloat = 0
    var horizontalScrollPosition: CGFloat = 0
    
    // MARK: - Feedback Loop Prevention
    var isUpdatingVertical = false
    var isUpdatingHorizontal = false
    
    // MARK: - DAW-Specific Configuration
    private let headerWidth: CGFloat = 280  // Match TellUrStori track header width
    private let timelineRulerHeight: CGFloat = 40  // Match existing ruler height
    
    // MARK: - User-Initiated Updates
    func updateVerticalPosition(_ position: CGFloat) {
        guard !isUpdatingVertical else { return }
        verticalScrollPosition = max(0, min(1, position))
    }
    
    func updateHorizontalPosition(_ position: CGFloat) {
        guard !isUpdatingHorizontal else { return }
        horizontalScrollPosition = max(0, min(1, position))
    }
    
    // MARK: - Programmatic Updates (Prevents Feedback Loops)
    func setVerticalPosition(_ position: CGFloat) {
        isUpdatingVertical = true
        verticalScrollPosition = max(0, min(1, position))
        
        // Reset flag after UI updates complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isUpdatingVertical = false
        }
    }
    
    func setHorizontalPosition(_ position: CGFloat) {
        isUpdatingHorizontal = true
        horizontalScrollPosition = max(0, min(1, position))
        
        // Reset flag after UI updates complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isUpdatingHorizontal = false
        }
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
        
        // Calculate width based on project duration and zoom
        let projectDuration = project.duration ?? 60.0 // Default 60 seconds
        let pixelsPerSecond = 100.0 * horizontalZoom
        let contentWidth = projectDuration * pixelsPerSecond
        
        // Calculate height based on track count and zoom
        let trackHeight = 80.0 * verticalZoom
        let contentHeight = Double(project.tracks.count) * trackHeight
        
        return CGSize(width: contentWidth, height: contentHeight)
    }
}
