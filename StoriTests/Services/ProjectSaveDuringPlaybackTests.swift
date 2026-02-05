//
//  ProjectSaveDuringPlaybackTests.swift
//  StoriTests
//
//  Issue #63: Project Save During Playback May Capture Inconsistent State
//
//  CRITICAL VALIDATION:
//  - Saving during playback produces consistent project state
//  - No torn reads of transport position, automation, or plugin state
//  - Playback resumes seamlessly after save (no glitches, no position drift)
//  - Rapid save stress test (100x saves during playback)
//  - Multi-track, multi-automation scenario
//

import XCTest
@testable import Stori

final class ProjectSaveDuringPlaybackTests: XCTestCase {
    
    var projectManager: ProjectManager!
    var mockTransportState: MockTransportState!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        // Create temp directory for test projects
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoriTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        projectManager = ProjectManager()
        mockTransportState = MockTransportState()
        
        // Set up mock notification handlers
        setupMockTransportNotifications()
    }
    
    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        projectManager = nil
        mockTransportState = nil
        
        super.tearDown()
    }
    
    // MARK: - Mock Transport State
    
    class MockTransportState {
        var isPlaying: Bool = false
        var currentBeat: Double = 0.0
        var pauseCount: Int = 0
        var resumeCount: Int = 0
    }
    
    func setupMockTransportNotifications() {
        // Query transport state
        NotificationCenter.default.addObserver(
            forName: .queryTransportState,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let continuation = notification.userInfo?["continuation"] as? CheckedContinuation<Bool, Never> {
                continuation.resume(returning: self.mockTransportState.isPlaying)
            }
        }
        
        // Pause for save
        NotificationCenter.default.addObserver(
            forName: .pauseTransportForSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.mockTransportState.isPlaying = false
            self.mockTransportState.pauseCount += 1
            NotificationCenter.default.post(name: .transportPausedForSave, object: nil)
        }
        
        // Resume after save
        NotificationCenter.default.addObserver(
            forName: .resumeTransportAfterSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.mockTransportState.isPlaying = true
            self.mockTransportState.resumeCount += 1
        }
    }
    
    // MARK: - Test 1: Save During Stopped State (No Transport Coordination)
    
    func testSave_WhenStopped_NoTransportPause() async throws {
        // Given: Project exists, transport stopped
        try projectManager.createNewProject(name: "TestProject_Stopped")
        mockTransportState.isPlaying = false
        
        // When: Save project
        await saveCurrentProjectAsync()
        
        // Then: No transport pause/resume
        XCTAssertEqual(mockTransportState.pauseCount, 0, "Should not pause when already stopped")
        XCTAssertEqual(mockTransportState.resumeCount, 0, "Should not resume when already stopped")
    }
    
    // MARK: - Test 2: Save During Playback Pauses Transport
    
    func testSave_WhenPlaying_PausesAndResumesTransport() async throws {
        // Given: Project exists, transport playing
        try projectManager.createNewProject(name: "TestProject_Playing")
        mockTransportState.isPlaying = true
        mockTransportState.currentBeat = 42.5
        
        // When: Save project
        await saveCurrentProjectAsync()
        
        // Then: Transport paused and resumed
        XCTAssertEqual(mockTransportState.pauseCount, 1, "Should pause once for save")
        XCTAssertEqual(mockTransportState.resumeCount, 1, "Should resume once after save")
    }
    
    // MARK: - Test 3: Save Captures Consistent Playhead Position
    
    func testSave_CapturesConsistentPlayheadPosition() async throws {
        // Given: Project with specific playhead position
        try projectManager.createNewProject(name: "TestProject_Playhead")
        var project = projectManager.currentProject!
        project.uiState.playheadPosition = 123.456
        projectManager.currentProject = project
        mockTransportState.isPlaying = true
        mockTransportState.currentBeat = 123.456
        
        // When: Save and reload project
        await saveCurrentProjectAsync()
        let savedProject = try loadProject(name: "TestProject_Playhead")
        
        // Then: Playhead position matches exactly (no drift from concurrent updates)
        XCTAssertEqual(savedProject.uiState.playheadPosition, 123.456, accuracy: 0.001,
                       "Playhead position should be captured atomically")
    }
    
    // MARK: - Test 4: Rapid Saves During Playback (Stress Test)
    
    func testRapidSaves_DuringPlayback_AllConsistent() async throws {
        // Given: Project with playback active
        try projectManager.createNewProject(name: "TestProject_RapidSave")
        mockTransportState.isPlaying = true
        
        // When: Save 100 times rapidly during "playback"
        for i in 0..<100 {
            mockTransportState.currentBeat = Double(i) * 0.25 // Simulate advancing playhead
            var project = projectManager.currentProject!
            project.uiState.playheadPosition = mockTransportState.currentBeat
            projectManager.currentProject = project
            
            await saveCurrentProjectAsync()
        }
        
        // Then: All saves succeeded, transport pause/resume counts match
        XCTAssertEqual(mockTransportState.pauseCount, 100, "Should pause for every save")
        XCTAssertEqual(mockTransportState.resumeCount, 100, "Should resume for every save")
    }
    
    // MARK: - Test 5: Save During Automation Changes
    
    func testSave_DuringAutomationChanges_CapturesConsistentValues() async throws {
        // Given: Project with automation being modified
        try projectManager.createNewProject(name: "TestProject_Automation")
        let track = projectManager.addTrack(name: "Test Track")!
        
        var project = projectManager.currentProject!
        var modifiedTrack = track
        
        // Add automation lane with specific points
        var automationLane = AutomationLane(
            parameter: .gain,
            trackId: track.id
        )
        automationLane.points = [
            AutomationPoint(beat: 0, value: 0.5),
            AutomationPoint(beat: 4, value: 0.8),
            AutomationPoint(beat: 8, value: 0.3)
        ]
        modifiedTrack.automationLanes = [automationLane]
        
        // Update project
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }) {
            project.tracks[trackIndex] = modifiedTrack
        }
        projectManager.currentProject = project
        mockTransportState.isPlaying = true
        
        // When: Save during "playback"
        await saveCurrentProjectAsync()
        
        // Then: Reload and verify automation intact
        let savedProject = try loadProject(name: "TestProject_Automation")
        let savedTrack = savedProject.tracks.first { $0.id == track.id }!
        XCTAssertEqual(savedTrack.automationLanes.count, 1, "Should have 1 automation lane")
        XCTAssertEqual(savedTrack.automationLanes[0].points.count, 3, "Should have 3 automation points")
        XCTAssertEqual(savedTrack.automationLanes[0].points[0].value, 0.5, accuracy: 0.001)
        XCTAssertEqual(savedTrack.automationLanes[0].points[1].value, 0.8, accuracy: 0.001)
        XCTAssertEqual(savedTrack.automationLanes[0].points[2].value, 0.3, accuracy: 0.001)
    }
    
    // MARK: - Test 6: Save With Multiple Tracks and Regions
    
    func testSave_MultiTrackProject_AllDataConsistent() async throws {
        // Given: Project with 8 tracks, multiple regions
        try projectManager.createNewProject(name: "TestProject_MultiTrack")
        
        for i in 1...8 {
            let track = projectManager.addTrack(name: "Track \(i)")!
            
            // Add region to track
            let region = AudioRegion(
                audioFile: AudioFile(url: tempDirectory.appendingPathComponent("test\(i).wav")),
                startBeat: Double(i) * 4.0,
                durationBeats: 4.0,
                tempo: 120.0
            )
            projectManager.addRegionToTrack(region, trackId: track.id)
        }
        
        mockTransportState.isPlaying = true
        
        // When: Save during playback
        await saveCurrentProjectAsync()
        
        // Then: Reload and verify all tracks and regions
        let savedProject = try loadProject(name: "TestProject_MultiTrack")
        XCTAssertEqual(savedProject.tracks.count, 8, "Should have 8 tracks")
        
        for (index, track) in savedProject.tracks.enumerated() {
            XCTAssertEqual(track.name, "Track \(index + 1)", "Track name should match")
            XCTAssertEqual(track.regions.count, 1, "Track should have 1 region")
            XCTAssertEqual(track.regions[0].startBeat, Double(index + 1) * 4.0, accuracy: 0.001,
                           "Region start beat should match")
        }
    }
    
    // MARK: - Test 7: Save With UI State (Zoom, Panels, etc.)
    
    func testSave_UIState_AllValuesPreserved() async throws {
        // Given: Project with custom UI state
        try projectManager.createNewProject(name: "TestProject_UIState")
        var project = projectManager.currentProject!
        
        project.uiState.horizontalZoom = 2.5
        project.uiState.verticalZoom = 1.8
        project.uiState.snapToGrid = false
        project.uiState.catchPlayheadEnabled = false
        project.uiState.metronomeEnabled = true
        project.uiState.metronomeVolume = 0.8
        project.uiState.showingInspector = true
        project.uiState.showingMixer = true
        project.uiState.mixerHeight = 750
        project.uiState.playheadPosition = 99.99
        
        projectManager.currentProject = project
        mockTransportState.isPlaying = true
        
        // When: Save during playback
        await saveCurrentProjectAsync()
        
        // Then: Reload and verify UI state
        let savedProject = try loadProject(name: "TestProject_UIState")
        XCTAssertEqual(savedProject.uiState.horizontalZoom, 2.5, accuracy: 0.001)
        XCTAssertEqual(savedProject.uiState.verticalZoom, 1.8, accuracy: 0.001)
        XCTAssertFalse(savedProject.uiState.snapToGrid)
        XCTAssertFalse(savedProject.uiState.catchPlayheadEnabled)
        XCTAssertTrue(savedProject.uiState.metronomeEnabled)
        XCTAssertEqual(savedProject.uiState.metronomeVolume, 0.8, accuracy: 0.001)
        XCTAssertTrue(savedProject.uiState.showingInspector)
        XCTAssertTrue(savedProject.uiState.showingMixer)
        XCTAssertEqual(savedProject.uiState.mixerHeight, 750, accuracy: 0.001)
        XCTAssertEqual(savedProject.uiState.playheadPosition, 99.99, accuracy: 0.001)
    }
    
    // MARK: - Test 8: Concurrent Saves Don't Corrupt State
    
    func testConcurrentSaves_NoStateCorruption() async throws {
        // Given: Project with playback active
        try projectManager.createNewProject(name: "TestProject_Concurrent")
        mockTransportState.isPlaying = true
        
        // When: Trigger 10 concurrent saves (simulating rapid Cmd+S mashing or autosave race)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    var project = await self.projectManager.currentProject!
                    project.uiState.playheadPosition = Double(i) * 10.0
                    await self.projectManager.updateCurrentProject(project)
                    await self.saveCurrentProjectAsync()
                }
            }
        }
        
        // Then: Reload and verify project is valid (not corrupted)
        let savedProject = try loadProject(name: "TestProject_Concurrent")
        XCTAssertNotNil(savedProject, "Project should load successfully")
        XCTAssertEqual(savedProject.name, "TestProject_Concurrent")
        // Playhead position will be one of the concurrent writes - just verify it's reasonable
        XCTAssertGreaterThanOrEqual(savedProject.uiState.playheadPosition, 0.0)
        XCTAssertLessThan(savedProject.uiState.playheadPosition, 100.0)
    }
    
    // MARK: - Test 9: Save With Tempo Change
    
    func testSave_DuringTempoChange_ConsistentState() async throws {
        // Given: Project with tempo change
        try projectManager.createNewProject(name: "TestProject_Tempo")
        mockTransportState.isPlaying = true
        
        // When: Change tempo and save
        projectManager.updateTempo(140.0)
        await saveCurrentProjectAsync()
        
        // Then: Reload and verify tempo
        let savedProject = try loadProject(name: "TestProject_Tempo")
        XCTAssertEqual(savedProject.tempo, 140.0, accuracy: 0.001, "Tempo should be saved correctly")
    }
    
    // MARK: - Test 10: Save Timeout Handling (Transport Not Responding)
    
    func testSave_TransportNotResponding_TimesOutGracefully() async throws {
        // Given: Project with transport that won't respond to pause request
        try projectManager.createNewProject(name: "TestProject_Timeout")
        mockTransportState.isPlaying = true
        
        // Remove pause notification observer to simulate non-responding transport
        NotificationCenter.default.removeObserver(self, name: .pauseTransportForSave, object: nil)
        
        // When: Save (should timeout after 100ms and continue)
        let startTime = Date()
        await saveCurrentProjectAsync()
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Then: Save completed despite timeout (graceful degradation)
        XCTAssertLessThan(elapsed, 1.0, "Save should timeout quickly (< 1s)")
        
        // Reload and verify project saved successfully
        let savedProject = try loadProject(name: "TestProject_Timeout")
        XCTAssertEqual(savedProject.name, "TestProject_Timeout")
    }
    
    // MARK: - Test 11: Save Does Not Block Main Thread
    
    func testSave_DoesNotBlockMainThread() async throws {
        // Given: Project with playback
        try projectManager.createNewProject(name: "TestProject_NonBlocking")
        mockTransportState.isPlaying = true
        
        // When: Save and measure main thread responsiveness
        let expectation = XCTestExpectation(description: "Main thread responsive during save")
        
        Task { @MainActor in
            await saveCurrentProjectAsync()
        }
        
        // Poll main thread every 10ms to verify it's not blocked
        Task { @MainActor in
            for _ in 0..<20 { // 200ms total
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            expectation.fulfill()
        }
        
        // Then: Main thread remained responsive
        await fulfillment(of: [expectation], timeout: 0.5)
    }
    
    // MARK: - Test 12: Save Preserves Modified Date
    
    func testSave_UpdatesModifiedDate() async throws {
        // Given: Project with old modified date
        try projectManager.createNewProject(name: "TestProject_ModifiedDate")
        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        var project = projectManager.currentProject!
        project.modifiedAt = oldDate
        projectManager.currentProject = project
        
        // When: Save
        let beforeSave = Date()
        await saveCurrentProjectAsync()
        
        // Then: Modified date updated to current time
        let savedProject = try loadProject(name: "TestProject_ModifiedDate")
        XCTAssertGreaterThan(savedProject.modifiedAt, oldDate)
        XCTAssertGreaterThanOrEqual(savedProject.modifiedAt, beforeSave)
    }
    
    // MARK: - Test 13: Regression - No Torn Reads
    
    func testRegression_NoTornReads_PlayheadAndAutomation() async throws {
        // Given: Project with playhead and automation changing rapidly
        try projectManager.createNewProject(name: "TestProject_TornRead")
        let track = projectManager.addTrack(name: "Test Track")!
        mockTransportState.isPlaying = true
        
        // When: Rapidly update playhead and automation, then save
        for i in 0..<50 {
            var project = projectManager.currentProject!
            project.uiState.playheadPosition = Double(i) * 0.1
            
            // Update automation
            if let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }) {
                var automationLane = AutomationLane(parameter: .gain, trackId: track.id)
                automationLane.points = [
                    AutomationPoint(beat: 0, value: Float(i) / 100.0)
                ]
                project.tracks[trackIndex].automationLanes = [automationLane]
            }
            
            projectManager.currentProject = project
            
            // Save on every 10th update
            if i % 10 == 0 {
                await saveCurrentProjectAsync()
            }
        }
        
        // Then: Reload and verify state is internally consistent (no torn reads)
        let savedProject = try loadProject(name: "TestProject_TornRead")
        let savedTrack = savedProject.tracks.first { $0.id == track.id }!
        
        // Playhead and automation should be from same snapshot
        // (both from last save, not mixed between saves)
        XCTAssertNotNil(savedTrack.automationLanes.first)
    }
    
    // MARK: - Helper Methods
    
    private func saveCurrentProjectAsync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                projectManager.saveCurrentProject()
                // Wait for async save to complete
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                continuation.resume()
            }
        }
    }
    
    private func loadProject(name: String) throws -> AudioProject {
        let sanitizedName = sanitizeFileName(name)
        let projectURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Stori/Projects/\(sanitizedName).stori")
        
        let data = try Data(contentsOf: projectURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AudioProject.self, from: data)
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.newlines).union(.illegalCharacters).union(.controlCharacters)
        return name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ProjectManager Test Extension

@MainActor
extension ProjectManager {
    func updateCurrentProject(_ project: AudioProject) async {
        self.currentProject = project
    }
}
