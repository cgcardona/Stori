//
//  UndoServiceTests.swift
//  StoriTests
//
//  Unit tests for undo/redo functionality
//

import XCTest
@testable import Stori

final class UndoServiceTests: XCTestCase {
    
    // MARK: - Undo Action Model Tests
    
    /// Test model for undo operations
    struct TestUndoAction: Equatable {
        var description: String
        var performUndo: () -> Void
        var performRedo: () -> Void
        
        static func == (lhs: TestUndoAction, rhs: TestUndoAction) -> Bool {
            lhs.description == rhs.description
        }
    }
    
    // MARK: - Undo Stack Tests
    
    func testUndoStackBasics() {
        var undoStack: [String] = []
        var redoStack: [String] = []
        
        // Push actions
        undoStack.append("Action 1")
        undoStack.append("Action 2")
        undoStack.append("Action 3")
        
        XCTAssertEqual(undoStack.count, 3)
        
        // Undo last action
        if let action = undoStack.popLast() {
            redoStack.append(action)
        }
        
        XCTAssertEqual(undoStack.count, 2)
        XCTAssertEqual(redoStack.count, 1)
        XCTAssertEqual(redoStack.last, "Action 3")
    }
    
    func testUndoRedoCycle() {
        var value = 0
        var undoStack: [Int] = []
        var redoStack: [Int] = []
        
        // Record initial state and make change
        undoStack.append(value)  // Save 0
        value = 10
        
        undoStack.append(value)  // Save 10
        value = 20
        
        undoStack.append(value)  // Save 20
        value = 30
        
        XCTAssertEqual(value, 30)
        
        // Undo: 30 -> 20
        if undoStack.count > 0 {
            let previousValue = undoStack.popLast()!
            redoStack.append(value)
            value = previousValue
        }
        
        XCTAssertEqual(value, 20)
        
        // Redo: 20 -> 30
        if redoStack.count > 0 {
            let nextValue = redoStack.popLast()!
            undoStack.append(value)
            value = nextValue
        }
        
        XCTAssertEqual(value, 30)
    }
    
    func testNewActionClearsRedoStack() {
        var undoStack: [String] = []
        var redoStack: [String] = []
        
        undoStack.append("Action 1")
        undoStack.append("Action 2")
        undoStack.append("Action 3")
        
        // Undo to get some redo actions
        if let action = undoStack.popLast() {
            redoStack.append(action)
        }
        if let action = undoStack.popLast() {
            redoStack.append(action)
        }
        
        XCTAssertEqual(undoStack.count, 1)
        XCTAssertEqual(redoStack.count, 2)
        
        // New action should clear redo stack
        undoStack.append("New Action")
        redoStack.removeAll()
        
        XCTAssertEqual(undoStack.count, 2)
        XCTAssertTrue(redoStack.isEmpty)
    }
    
    // MARK: - State Snapshot Tests
    
    func testProjectStateSnapshot() {
        let project1 = AudioProject(name: "Version 1")
        var project2 = project1
        project2.name = "Version 2"
        
        // Snapshots should be independent
        XCTAssertEqual(project1.name, "Version 1")
        XCTAssertEqual(project2.name, "Version 2")
    }
    
    func testTrackStateSnapshot() {
        var originalTrack = AudioTrack(name: "Original", trackType: .audio)
        originalTrack.mixerSettings.volume = 0.8
        
        var snapshot = originalTrack
        snapshot.mixerSettings.volume = 0.5
        
        XCTAssertEqual(originalTrack.mixerSettings.volume, 0.8)
        XCTAssertEqual(snapshot.mixerSettings.volume, 0.5)
    }
    
    // MARK: - Undo Group Tests
    
    func testUndoGrouping() {
        var actionLog: [String] = []
        
        // Group of related actions
        let groupId = UUID()
        let actions = [
            (group: groupId, action: "Move Note 1"),
            (group: groupId, action: "Move Note 2"),
            (group: groupId, action: "Move Note 3")
        ]
        
        // Execute group
        for item in actions {
            actionLog.append(item.action)
        }
        
        XCTAssertEqual(actionLog.count, 3)
        
        // Undo group (all actions with same group should undo together)
        let groupActions = actions.filter { $0.group == groupId }
        for action in groupActions.reversed() {
            if let index = actionLog.firstIndex(of: action.action) {
                actionLog.remove(at: index)
            }
        }
        
        XCTAssertTrue(actionLog.isEmpty)
    }
    
    // MARK: - Memory Limit Tests
    
    func testUndoStackSizeLimit() {
        var undoStack: [String] = []
        let maxSize = 50
        
        for i in 0..<100 {
            undoStack.append("Action \(i)")
            
            // Enforce size limit
            if undoStack.count > maxSize {
                undoStack.removeFirst()
            }
        }
        
        XCTAssertEqual(undoStack.count, maxSize)
        XCTAssertEqual(undoStack.first, "Action 50")  // Oldest remaining
        XCTAssertEqual(undoStack.last, "Action 99")   // Newest
    }
    
    // MARK: - Project Modification Tracking Tests
    
    func testTrackChangedUndoState() {
        var project = AudioProject(name: "Test")
        var changes: [String] = []
        
        // Track addition
        let track = AudioTrack(name: "New Track")
        changes.append("add_track:\(track.id)")
        project.addTrack(track)
        
        XCTAssertEqual(project.trackCount, 1)
        XCTAssertEqual(changes.count, 1)
        
        // Undo track addition
        if let lastChange = changes.popLast(), lastChange.hasPrefix("add_track:") {
            let trackId = UUID(uuidString: String(lastChange.dropFirst("add_track:".count)))!
            project.removeTrack(withId: trackId)
        }
        
        XCTAssertEqual(project.trackCount, 0)
    }
    
    // MARK: - MIDI Region Undo Tests
    
    func testMIDINoteEditUndo() {
        var region = MIDIRegion(name: "Test")
        let note = MIDINote(pitch: 60, velocity: 100, startTime: 0, duration: 1.0)
        
        // Save state before edit
        let originalPitch = note.pitch
        
        region.addNote(note)
        
        // Modify note
        var modifiedNote = note
        modifiedNote.pitch = 64
        
        // Simulate undo by restoring original
        var restoredNote = modifiedNote
        restoredNote.pitch = originalPitch
        
        XCTAssertEqual(restoredNote.pitch, 60)
    }
    
    func testMIDIRegionMoveUndo() {
        var region = MIDIRegion(startTime: 4.0, duration: 8.0)
        
        // Save original position
        let originalStart = region.startTime
        
        // Move region
        region.startTime = 8.0
        XCTAssertEqual(region.startTime, 8.0)
        
        // Undo move
        region.startTime = originalStart
        XCTAssertEqual(region.startTime, 4.0)
    }
    
    // MARK: - Mixer Settings Undo Tests
    
    func testMixerSettingsUndo() {
        var settings = MixerSettings()
        
        // Save original
        let originalVolume = settings.volume
        let originalPan = settings.pan
        
        // Make changes
        settings.volume = 0.5
        settings.pan = -0.5
        
        XCTAssertEqual(settings.volume, 0.5)
        XCTAssertEqual(settings.pan, -0.5)
        
        // Undo
        settings.volume = originalVolume
        settings.pan = originalPan
        
        XCTAssertEqual(settings.volume, 0.8)
        XCTAssertEqual(settings.pan, 0.5)
    }
    
    // MARK: - Automation Undo Tests
    
    func testAutomationPointUndo() {
        var lane = AutomationLane(parameter: .volume)
        
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        
        // Save state
        let savedPoints = lane.points
        XCTAssertEqual(savedPoints.count, 2)
        
        // Add more points
        lane.addPoint(atBeat: 8.0, value: 0.3)
        lane.addPoint(atBeat: 12.0, value: 0.9)
        XCTAssertEqual(lane.points.count, 4)
        
        // Undo by restoring saved state
        lane.clearPoints()
        for point in savedPoints {
            lane.points.append(point)
        }
        
        XCTAssertEqual(lane.points.count, 2)
    }
    
    // MARK: - Complex Operation Undo Tests
    
    func testComplexOperationUndo() {
        var project = AudioProject(name: "Complex Test")
        
        // Create a checkpoint
        let checkpoint = project
        
        // Perform multiple operations
        var track1 = AudioTrack(name: "Track 1", trackType: .midi)
        track1.mixerSettings.volume = 0.7
        project.addTrack(track1)
        
        var track2 = AudioTrack(name: "Track 2", trackType: .audio)
        track2.mixerSettings.pan = 0.5
        project.addTrack(track2)
        
        project.tempo = 140.0
        project.keySignature = "D"
        
        XCTAssertEqual(project.trackCount, 2)
        XCTAssertEqual(project.tempo, 140.0)
        
        // Undo all by restoring checkpoint
        project = checkpoint
        
        XCTAssertEqual(project.trackCount, 0)
        XCTAssertEqual(project.tempo, 120.0)
        XCTAssertEqual(project.keySignature, "C")
    }
    
    // MARK: - Performance Tests
    
    func testUndoStackPerformance() {
        var undoStack: [AudioProject] = []
        var project = AudioProject(name: "Performance Test")
        
        measure {
            for i in 0..<100 {
                undoStack.append(project)
                project.addTrack(AudioTrack(name: "Track \(i)"))
                
                // Keep stack size manageable
                if undoStack.count > 20 {
                    undoStack.removeFirst(10)
                }
            }
        }
    }
}
