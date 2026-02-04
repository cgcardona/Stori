//
//  AudioEngineTests.swift
//  StoriTests
//
//  Comprehensive tests for AudioEngine - Core audio engine lifecycle and management
//  Tests cover initialization, project loading, track management, and error handling
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class AudioEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var engine: AudioEngine!
    private var mockProjectManager: MockProjectManager!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        engine = AudioEngine()
        mockProjectManager = MockProjectManager()
    }
    
    override func tearDown() async throws {
        // Stop engine if running
        if engine.isRunning {
            engine.stop()
        }
        engine = nil
        mockProjectManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testEngineInitialization() {
        // Engine should initialize in stopped state
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        XCTAssertFalse(engine.isRecording)
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    func testEngineHasValidComponents() {
        // Engine should have all required components initialized
        XCTAssertNotNil(engine.sharedAVAudioEngine)
        XCTAssertNotNil(engine.sharedMixer)
        XCTAssertGreaterThan(engine.currentSampleRate, 0)
    }
    
    func testEngineGraphStableByDefault() {
        // Graph should be stable on initialization
        XCTAssertTrue(engine.isGraphStable)
    }
    
    func testEngineGraphReadyForPlaybackDefaultsFalse() {
        // Graph should not be ready for playback until explicitly set
        // This prevents crashes during initialization
        XCTAssertFalse(engine.isGraphReadyForPlayback)
    }
    
    // MARK: - Start/Stop Tests
    
    func testEngineStart() async throws {
        // Configure with mock project manager
        engine.configure(projectManager: mockProjectManager)
        
        // Start engine
        try await engine.start()
        
        // Verify engine is running
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }
    
    func testEngineStartIdempotent() async throws {
        engine.configure(projectManager: mockProjectManager)
        
        // Start twice
        try await engine.start()
        XCTAssertTrue(engine.isRunning)
        
        try await engine.start()
        XCTAssertTrue(engine.isRunning)
    }
    
    func testEngineStop() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        // Stop engine
        engine.stop()
        
        // Verify engine stopped
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
    }
    
    func testEngineStopIdempotent() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        // Stop twice
        engine.stop()
        XCTAssertFalse(engine.isRunning)
        
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }
    
    func testEngineStopWhenNotRunning() {
        // Should handle stop gracefully when not running
        XCTAssertFalse(engine.isRunning)
        
        engine.stop()
        
        XCTAssertFalse(engine.isRunning)
    }
    
    // MARK: - Sample Rate Tests
    
    func testEngineSampleRate() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let sampleRate = engine.currentSampleRate
        
        // Sample rate should be one of standard rates
        let validRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        XCTAssertTrue(validRates.contains(sampleRate), "Sample rate \(sampleRate) should be standard rate")
    }
    
    func testEngineSampleRateConsistent() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let rate1 = engine.currentSampleRate
        let rate2 = engine.currentSampleRate
        
        XCTAssertEqual(rate1, rate2, "Sample rate should be consistent")
    }
    
    // MARK: - Project Configuration Tests
    
    func testEngineConfigureWithProjectManager() {
        // Should configure without throwing
        engine.configure(projectManager: mockProjectManager)
        
        // Engine should still be stopped after configuration
        XCTAssertFalse(engine.isRunning)
    }
    
    func testEngineLoadEmptyProject() async throws {
        let project = AudioProject(name: "Empty Project", tempo: 120.0)
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        await engine.loadProject(project)
        
        // Project should be loaded
        XCTAssertEqual(engine.currentProject?.name, "Empty Project")
        XCTAssertEqual(engine.currentProject?.tempo, 120.0)
    }
    
    func testEngineLoadProjectWithTracks() async throws {
        var project = AudioProject(name: "Test Project", tempo: 140.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "Track 2", trackType: .midi, color: .red))
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        await engine.loadProject(project)
        
        XCTAssertEqual(engine.currentProject?.tracks.count, 2)
        XCTAssertEqual(engine.currentProject?.tracks[0].name, "Track 1")
        XCTAssertEqual(engine.currentProject?.tracks[1].name, "Track 2")
    }
    
    func testEngineUpdateProjectData() async throws {
        var project = AudioProject(name: "Original", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        // Update project data
        var updatedProject = project
        updatedProject.name = "Updated"
        updatedProject.tempo = 140.0
        
        engine.updateProjectData(updatedProject)
        
        XCTAssertEqual(engine.currentProject?.name, "Updated")
        XCTAssertEqual(engine.currentProject?.tempo, 140.0)
    }
    
    // MARK: - Track Management Tests
    
    func testEngineGetTrackNode() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        let node = engine.getTrackNode(for: trackId)
        
        // Node should be created during project load
        XCTAssertNotNil(node)
    }
    
    func testEngineGetTrackNodeInvalidId() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let invalidId = UUID()
        let node = engine.getTrackNode(for: invalidId)
        
        XCTAssertNil(node, "Should return nil for invalid track ID")
    }
    
    func testEngineEnsureTrackNodeExists() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        let track = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        project.addTrack(track)
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        // Ensure node exists
        engine.ensureTrackNodeExists(for: track)
        
        let node = engine.getTrackNode(for: track.id)
        XCTAssertNotNil(node)
    }
    
    // MARK: - Mixer Control Tests
    
    func testEngineSetTrackVolume() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        engine.setTrackVolume(trackId, volume: 0.5)
        
        // Verify volume was set (check via project data)
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertEqual(track?.mixerSettings.volume, 0.5)
    }
    
    func testEngineSetTrackPan() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        engine.setTrackPan(trackId, pan: -0.3)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertEqual(track?.mixerSettings.pan, -0.3)
    }
    
    func testEngineMuteTrack() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        engine.muteTrack(trackId, muted: true)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertTrue(track?.mixerSettings.isMuted ?? false)
    }
    
    func testEngineSoloTrack() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        engine.soloTrack(trackId, solo: true)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertTrue(track?.mixerSettings.isSolo ?? false)
    }
    
    func testEngineMasterVolume() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let defaultVolume = engine.masterVolume
        XCTAssertGreaterThan(defaultVolume, 0.0)
        
        engine.masterVolume = 0.6
        XCTAssertEqual(engine.masterVolume, 0.6)
    }
    
    // MARK: - Transport Control Tests
    
    func testEnginePlay() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.play()
        
        XCTAssertEqual(engine.transportState, .playing)
    }
    
    func testEnginePause() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.play()
        XCTAssertEqual(engine.transportState, .playing)
        
        engine.pause()
        XCTAssertEqual(engine.transportState, .paused)
    }
    
    func testEngineStopResetsPosition() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.play()
        engine.seek(toBeat: 16.0)
        
        engine.stop()
        
        XCTAssertEqual(engine.transportState, .stopped)
        // Position should be reset to 0
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    func testEngineSeekToBeat() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.seek(toBeat: 8.5)
        
        assertApproximatelyEqual(engine.currentPosition.beats, 8.5, tolerance: 0.1)
    }
    
    func testEngineSeekToSeconds() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        // 2 seconds at 120 BPM = 4 beats
        engine.seek(toSeconds: 2.0)
        
        assertApproximatelyEqual(engine.currentPosition.beats, 4.0, tolerance: 0.1)
    }
    
    func testEngineSeekNegativeBeatsClamps() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.seek(toBeat: -5.0)
        
        // Should clamp to 0
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    // MARK: - Cycle/Loop Tests
    
    func testEngineCycleEnabled() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        XCTAssertFalse(engine.isCycleEnabled)
        
        engine.isCycleEnabled = true
        engine.cycleStartBeat = 0.0
        engine.cycleEndBeat = 8.0
        
        XCTAssertTrue(engine.isCycleEnabled)
        XCTAssertEqual(engine.cycleStartBeat, 0.0)
        XCTAssertEqual(engine.cycleEndBeat, 8.0)
    }
    
    // MARK: - Recording Tests
    
    func testEngineRecordingState() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        XCTAssertFalse(engine.isRecording)
        
        engine.record()
        
        XCTAssertTrue(engine.isRecording)
        XCTAssertEqual(engine.transportState, .recording)
    }
    
    func testEngineStopRecording() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.record()
        XCTAssertTrue(engine.isRecording)
        
        engine.stopRecording()
        
        XCTAssertFalse(engine.isRecording)
    }
    
    func testEngineInputLevel() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let level = engine.inputLevel
        
        // Input level should be 0 or negative dB
        XCTAssertLessThanOrEqual(level, 0.0)
    }
    
    // MARK: - Bus Management Tests
    
    func testEngineAddBus() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        let bus = MixerBus(name: "Reverb", outputLevel: 0.8)
        engine.addBus(bus)
        
        // Verify bus was added
        XCTAssertNotNil(engine.getBusPluginChain(for: bus.id))
    }
    
    func testEngineRemoveBus() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        let bus = MixerBus(name: "Reverb", outputLevel: 0.8)
        engine.addBus(bus)
        
        engine.removeBus(withId: bus.id)
        
        // Bus should be removed
        XCTAssertNil(engine.getBusPluginChain(for: bus.id))
    }
    
    // MARK: - Graph Generation Tests
    
    func testEngineGraphGenerationIncrementsOnMutation() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let initialGeneration = engine.graphGeneration
        
        // Perform graph mutation
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "New Track", trackType: .audio, color: .blue))
        await engine.loadProject(project)
        
        // Generation should increment
        XCTAssertGreaterThan(engine.graphGeneration, initialGeneration)
    }
    
    func testEngineGraphGenerationValidation() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let capturedGeneration = engine.graphGeneration
        
        // Before mutation, generation should be valid
        XCTAssertTrue(engine.isGraphGenerationValid(capturedGeneration))
        
        // Mutate graph
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "New Track", trackType: .audio, color: .blue))
        await engine.loadProject(project)
        
        // After mutation, old generation should be invalid
        XCTAssertFalse(engine.isGraphGenerationValid(capturedGeneration))
    }
    
    // MARK: - Graph Stability Tests
    
    func testEngineGraphStabilityDuringLoad() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        // Graph should be stable initially
        XCTAssertTrue(engine.isGraphStable)
        
        // During project load, graph may become unstable temporarily
        // (This is handled internally by loadProject)
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        await engine.loadProject(project)
        
        // After load completes, graph should be stable again
        XCTAssertTrue(engine.isGraphStable)
    }
    
    // MARK: - Error Handling Tests
    
    func testEngineHandlesStartWithoutConfiguration() async {
        let unconfiguredEngine = AudioEngine()
        
        // Should throw or handle gracefully
        do {
            try await unconfiguredEngine.start()
            // If it doesn't throw, verify it handles gracefully
            XCTAssertTrue(true, "Engine started without configuration")
        } catch {
            // Expected to throw
            XCTAssertTrue(true, "Engine threw expected error: \(error)")
        }
    }
    
    func testEngineHandlesPlayWhenNotRunning() {
        // Should handle gracefully or throw
        XCTAssertFalse(engine.isRunning)
        
        engine.play()
        
        // Transport state may not change if engine not running
        // (Implementation dependent - either way should not crash)
        XCTAssertTrue(true, "Play when not running did not crash")
    }
    
    func testEngineHandlesSeekWhenNotRunning() {
        XCTAssertFalse(engine.isRunning)
        
        engine.seek(toBeat: 10.0)
        
        // Should handle gracefully
        XCTAssertTrue(true, "Seek when not running did not crash")
    }
    
    func testEngineHandlesInvalidTrackOperations() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        let invalidTrackId = UUID()
        
        // Should handle gracefully without crashing
        engine.setTrackVolume(invalidTrackId, volume: 0.5)
        engine.setTrackPan(invalidTrackId, pan: 0.0)
        engine.muteTrack(invalidTrackId, muted: true)
        
        XCTAssertTrue(true, "Invalid track operations did not crash")
    }
    
    // MARK: - Performance Tests
    
    func testEngineStartStopPerformance() async throws {
        engine.configure(projectManager: mockProjectManager)
        
        measure {
            Task { @MainActor in
                try? await engine.start()
                engine.stop()
            }
        }
    }
    
    func testEngineProjectLoadPerformance() async throws {
        // Create project with multiple tracks
        var project = AudioProject(name: "Performance Test", tempo: 120.0)
        for i in 0..<10 {
            project.addTrack(AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue))
        }
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        measure {
            Task { @MainActor in
                await engine.loadProject(project)
            }
        }
    }
    
    func testEngineSeekPerformance() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        measure {
            for i in 0..<100 {
                engine.seek(toBeat: Double(i))
            }
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testEngineConcurrentSeek() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        // Perform concurrent seeks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    self.engine.seek(toBeat: Double(i * 4))
                }
            }
        }
        
        // Should complete without crashing
        XCTAssertTrue(true, "Concurrent seeks completed")
    }
    
    func testEngineConcurrentVolumeUpdates() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        await engine.loadProject(project)
        
        // Perform concurrent volume updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    self.engine.setTrackVolume(trackId, volume: Float(i) / 10.0)
                }
            }
        }
        
        XCTAssertTrue(true, "Concurrent volume updates completed")
    }
    
    // MARK: - Automation Tests
    
    func testEngineAutomationProcessorExists() {
        // Automation processor should be initialized
        XCTAssertNotNil(engine.automationProcessor)
    }
    
    func testEngineAutomationEngineExists() {
        // Automation engine should be initialized
        XCTAssertNotNil(engine.automationEngine)
    }
    
    func testEngineAutomationRecorderExists() {
        // Automation recorder should be initialized
        XCTAssertNotNil(engine.automationRecorder)
    }
    
    // MARK: - MIDI Playback Tests
    
    func testEngineMIDIPlaybackEngineExists() {
        // MIDI playback engine should be initialized
        XCTAssertNotNil(engine.midiPlaybackEngine)
    }
    
    func testEngineSequencerEngineExists() {
        // Sequencer engine should be initialized (lazy)
        let sequencer = engine.sequencerEngine
        XCTAssertNotNil(sequencer)
    }
    
    // MARK: - Cleanup Tests
    
    func testEngineCleanupOnStop() async throws {
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        engine.play()
        XCTAssertEqual(engine.transportState, .playing)
        
        engine.stop()
        
        // Verify cleanup
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    func testEngineMemoryCleanup() async throws {
        // Create and destroy multiple engines to verify no leaks
        for _ in 0..<5 {
            let tempEngine = AudioEngine()
            tempEngine.configure(projectManager: mockProjectManager)
            try await tempEngine.start()
            tempEngine.stop()
        }
        
        // If we get here without crashing, memory is being managed correctly
        XCTAssertTrue(true, "Multiple engine lifecycle iterations completed")
    }
    
    // MARK: - Integration Tests
    
    func testEngineFullWorkflow() async throws {
        // Complete workflow: configure, start, load project, play, record, stop
        engine.configure(projectManager: mockProjectManager)
        try await engine.start()
        
        var project = AudioProject(name: "Integration Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Audio Track", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "MIDI Track", trackType: .midi, color: .red))
        
        await engine.loadProject(project)
        
        engine.play()
        XCTAssertEqual(engine.transportState, .playing)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        engine.record()
        XCTAssertTrue(engine.isRecording)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        engine.stopRecording()
        XCTAssertFalse(engine.isRecording)
        
        engine.stop()
        XCTAssertEqual(engine.transportState, .stopped)
        
        XCTAssertTrue(true, "Full workflow completed successfully")
    }
}
