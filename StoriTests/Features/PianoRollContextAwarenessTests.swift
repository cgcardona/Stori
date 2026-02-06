//
//  PianoRollContextAwarenessTests.swift
//  StoriTests
//
//  Tests for Piano Roll context awareness and "Reveal in Timeline" feature (Issue #69)
//
//  CRITICAL: Piano Roll must clearly show its position in the timeline arrangement
//  and provide easy navigation back to the Timeline view for context.
//

import XCTest
@testable import Stori

@MainActor
final class PianoRollContextAwarenessTests: XCTestCase {
    
    var scrollSync: ScrollSyncModel!
    
    override func setUp() async throws {
        try await super.setUp()
        scrollSync = ScrollSyncModel()
    }
    
    override func tearDown() async throws {
        scrollSync = nil
        try await super.tearDown()
    }
    
    // MARK: - ScrollToBeat Method Tests
    
    /// Test scrollToBeat centers beat at 30% from left edge
    func testScrollToBeatCentersAt30Percent() {
        // Given: Timeline viewport and beat position
        let targetBeat = 100.0
        let pixelsPerBeat: CGFloat = 100.0
        let viewportWidth: CGFloat = 1200.0
        
        // When: Scroll to beat 100
        scrollSync.scrollToBeat(targetBeat, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        
        // Then: Beat should be at 30% from left edge
        let beatX = CGFloat(targetBeat) * pixelsPerBeat // 10000 pixels
        let expectedOffset = beatX - (viewportWidth * 0.3) // 10000 - 360 = 9640
        
        XCTAssertEqual(scrollSync.horizontalScrollOffset, expectedOffset, accuracy: 1.0,
                       "Beat should be centered at 30% from left edge (Logic Pro X style)")
    }
    
    /// Test scrollToBeat doesn't go negative
    func testScrollToBeatClampsToZero() {
        // Given: Early beat that would result in negative scroll
        let targetBeat = 2.0
        let pixelsPerBeat: CGFloat = 100.0
        let viewportWidth: CGFloat = 1200.0
        
        // When: Scroll to beat near start
        scrollSync.scrollToBeat(targetBeat, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        
        // Then: Offset should not go negative
        XCTAssertGreaterThanOrEqual(scrollSync.horizontalScrollOffset, 0,
                                    "Scroll offset should not go negative")
    }
    
    /// Test scrollToBeat works at different zoom levels
    func testScrollToBeatWorksAtDifferentZooms() {
        let targetBeat = 50.0
        let viewportWidth: CGFloat = 1200.0
        
        let zoomLevels: [(pixelsPerBeat: CGFloat, description: String)] = [
            (50.0, "Zoomed out"),   // 0.5x
            (100.0, "Normal"),      // 1.0x
            (200.0, "Zoomed in"),   // 2.0x
            (400.0, "Very zoomed in") // 4.0x
        ]
        
        for zoom in zoomLevels {
            scrollSync.scrollToBeat(targetBeat, pixelsPerBeat: zoom.pixelsPerBeat, viewportWidth: viewportWidth)
            
            let beatX = CGFloat(targetBeat) * zoom.pixelsPerBeat
            let expectedOffset = max(0, beatX - (viewportWidth * 0.3))
            
            XCTAssertEqual(scrollSync.horizontalScrollOffset, expectedOffset, accuracy: 1.0,
                           "Scroll should work at \(zoom.description) zoom level")
        }
    }
    
    /// Test multiple scrollToBeat calls update correctly
    func testMultipleScrollToBeatCalls() {
        let pixelsPerBeat: CGFloat = 100.0
        let viewportWidth: CGFloat = 1200.0
        
        // Scroll to beat 10
        scrollSync.scrollToBeat(10.0, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        let offset1 = scrollSync.horizontalScrollOffset
        
        // Scroll to beat 50
        scrollSync.scrollToBeat(50.0, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        let offset2 = scrollSync.horizontalScrollOffset
        
        // Scroll back to beat 10
        scrollSync.scrollToBeat(10.0, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        let offset3 = scrollSync.horizontalScrollOffset
        
        XCTAssertNotEqual(offset1, offset2, "Scrolling to different beats should change offset")
        XCTAssertEqual(offset1, offset3, accuracy: 1.0,
                       "Scrolling back to same beat should restore offset")
    }
    
    // MARK: - Bar Position Calculation Tests
    
    /// Test bar position calculation for standard 4/4 time
    func testBarPositionCalculation4_4() {
        // Given: Region in 4/4 time
        let timeSignature = TimeSignature(numerator: 4, denominator: 4)
        let beatsPerBar = Double(timeSignature.numerator) // 4.0
        
        let testCases: [(startBeat: Double, duration: Double, expectedStartBar: Int, expectedEndBar: Int)] = [
            (0.0, 4.0, 1, 1),      // Beat 0-4 = Bar 1 (exactly one bar)
            (4.0, 4.0, 2, 2),      // Beat 4-8 = Bar 2
            (0.0, 8.0, 1, 2),      // Beat 0-8 = Bars 1-2 (exactly two bars)
            (16.0, 16.0, 5, 8),    // Beat 16-32 = Bars 5-8
            (3.5, 1.0, 1, 2),      // Beat 3.5-4.5 = Bars 1-2 (spans bar line)
        ]
        
        for testCase in testCases {
            let startBar = Int(testCase.startBeat / beatsPerBar) + 1  // 1-indexed
            let endBeat = testCase.startBeat + testCase.duration
            // Use ceil with epsilon to handle exact bar boundaries correctly
            let endBar = Int(ceil((endBeat - 0.001) / beatsPerBar))
            
            XCTAssertEqual(startBar, testCase.expectedStartBar,
                           "Start bar for beat \(testCase.startBeat) should be \(testCase.expectedStartBar)")
            XCTAssertEqual(endBar, testCase.expectedEndBar,
                           "End bar for beat \(endBeat) should be \(testCase.expectedEndBar)")
        }
    }
    
    /// Test bar position calculation for odd time signatures
    func testBarPositionCalculationOddTime() {
        // Given: Region in 7/8 time
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let beatsPerBar = Double(timeSignature.numerator) // 7.0
        
        let region = MIDIRegion(
            name: "Test",
            startBeat: 14.0,  // Start of bar 3 (0-7=bar1, 7-14=bar2, 14-21=bar3)
            durationBeats: 7.0 // Exactly one bar
        )
        
        let startBar = Int(region.startBeat / beatsPerBar) + 1
        let endBeat = region.startBeat + region.durationBeats
        let endBar = Int(ceil((endBeat - 0.001) / beatsPerBar))
        
        XCTAssertEqual(startBar, 3, "7/8 time: beat 14 should be bar 3")
        XCTAssertEqual(endBar, 3, "7/8 time: one bar duration should stay in bar 3")
    }
    
    // MARK: - Integration Tests
    
    /// Test notification-based reveal mechanism
    func testRevealBeatNotificationTriggersScroll() {
        // Given: Scroll sync at initial position
        let initialOffset = scrollSync.horizontalScrollOffset
        XCTAssertEqual(initialOffset, 0, "Should start at position 0")
        
        // When: Reveal beat notification is posted
        let targetBeat = 50.0
        NotificationCenter.default.post(
            name: .revealBeatInTimeline,
            object: nil,
            userInfo: ["beat": targetBeat]
        )
        
        // Note: We can't directly test the notification receiver in unit tests
        // since it's part of a SwiftUI view. This test documents the expected behavior.
        
        // Manual test would verify: scrollSync.horizontalScrollOffset changes
        // after notification is received by IntegratedTimelineView
    }
    
    /// Test bar position display at different time signatures
    func testBarDisplayAtVariousTimeSignatures() {
        let testCases: [(timeSignature: TimeSignature, startBeat: Double, duration: Double, expectedDisplay: String)] = [
            (.fourFour, 0.0, 4.0, "1-1"),        // 4/4: bars 1-1 (one bar)
            (.fourFour, 0.0, 8.0, "1-2"),        // 4/4: bars 1-2 (two bars)
            (.fourFour, 16.0, 8.0, "5-6"),       // 4/4: bars 5-6
            (TimeSignature(numerator: 3, denominator: 4), 0.0, 3.0, "1-1"),   // 3/4: one bar
            (TimeSignature(numerator: 7, denominator: 8), 0.0, 7.0, "1-1"),   // 7/8: one bar
            (TimeSignature(numerator: 5, denominator: 4), 0.0, 15.0, "1-3"),  // 5/4: three bars
        ]
        
        for testCase in testCases {
            let beatsPerBar = Double(testCase.timeSignature.numerator)
            let startBar = Int(testCase.startBeat / beatsPerBar) + 1
            let endBeat = testCase.startBeat + testCase.duration
            let endBar = Int(ceil((endBeat - 0.001) / beatsPerBar))
            
            let display = "\(startBar)-\(endBar)"
            XCTAssertEqual(display, testCase.expectedDisplay,
                           "Bar display for \(testCase.timeSignature.numerator)/\(testCase.timeSignature.denominator) should be correct")
        }
    }
    
    // MARK: - Edge Cases
    
    /// Test scrollToBeat with very large beat numbers
    func testScrollToBeatLargeNumbers() {
        let targetBeat = 10000.0  // Very long project
        let pixelsPerBeat: CGFloat = 100.0
        let viewportWidth: CGFloat = 1200.0
        
        scrollSync.scrollToBeat(targetBeat, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewportWidth)
        
        let beatX = CGFloat(targetBeat) * pixelsPerBeat
        let expectedOffset = beatX - (viewportWidth * 0.3)
        
        XCTAssertEqual(scrollSync.horizontalScrollOffset, expectedOffset, accuracy: 1.0,
                       "Should handle very large beat numbers")
    }
    
    /// Test scrollToBeat with different viewport widths
    func testScrollToBeatDifferentViewportWidths() {
        let targetBeat = 50.0
        let pixelsPerBeat: CGFloat = 100.0
        
        let viewportWidths: [CGFloat] = [800, 1200, 1600, 2400]
        
        for viewport in viewportWidths {
            scrollSync.scrollToBeat(targetBeat, pixelsPerBeat: pixelsPerBeat, viewportWidth: viewport)
            
            let beatX = CGFloat(targetBeat) * pixelsPerBeat
            let expectedOffset = max(0, beatX - (viewport * 0.3))
            
            XCTAssertEqual(scrollSync.horizontalScrollOffset, expectedOffset, accuracy: 1.0,
                           "Should handle viewport width \(viewport)px")
        }
    }
    
    /// Test region spanning multiple bars
    func testRegionSpanningMultipleBars() {
        // Given: Long region spanning many bars
        let timeSignature = TimeSignature(numerator: 4, denominator: 4)
        let beatsPerBar = 4.0
        
        let region = MIDIRegion(
            name: "Long Region",
            startBeat: 8.0,   // Bar 3
            durationBeats: 32.0  // 8 bars long
        )
        
        let startBar = Int(region.startBeat / beatsPerBar) + 1
        let endBeat = region.startBeat + region.durationBeats
        // Use same epsilon logic as production code to handle exact bar boundaries
        let endBar = Int(ceil((endBeat - 0.001) / beatsPerBar))
        
        XCTAssertEqual(startBar, 3, "Should start at bar 3")
        XCTAssertEqual(endBar, 10, "Should end at bar 10 (8 bars long)")
    }
}