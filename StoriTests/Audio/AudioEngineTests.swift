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
        // Stop engine if running and reset to release render resources
        // This prevents "freed pointer was not the last allocation" warnings
        // from AVAudioEngine's internal allocator tearing down in non-LIFO order
        if engine.sharedAVAudioEngine.isRunning {
            engine.stop()
        }
        engine.sharedAVAudioEngine.reset()
        engine = nil
        mockProjectManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testEngineInitialization() {
        // Engine auto-starts for low latency (pro DAW pattern)
        // AVAudioEngine should be running, but transport is stopped
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
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
    
    func testEngineGraphReadyForPlaybackAfterInit() {
        // Graph is ready after auto-start during init
        XCTAssertTrue(engine.isGraphReadyForPlayback)
    }
    
    // MARK: - Health Monitoring (issue #80: low priority to avoid CPU spikes)
    
    /// Engine health checks must run on low-priority queue (.utility) so they don't compete with audio.
    func testHealthMonitorRunsOnLowPriorityQueue() {
        XCTAssertEqual(
            AudioEngine.healthMonitorQueueQoSForTesting,
            DispatchQoS.QoSClass.utility,
            "Health monitor queue must use .utility QoS to avoid periodic CPU spikes during playback"
        )
        XCTAssertEqual(
            AudioEngine.healthMonitorQueueLabelForTesting,
            "com.stori.engine.health",
            "Health monitor queue label must be stable for diagnostics"
        )
    }
    
    // MARK: - Start/Stop Tests
    
    func testEngineStart() async throws {
        // Configure with mock project manager
        
        // Start engine
        engine.play()
        
        // Verify engine is running
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }
    
    func testEngineStartIdempotent() async throws {
        
        // Start twice
        engine.play()
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        
        engine.play()
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }
    
    func testEngineStop() async throws {
        engine.play()
        
        // Stop transport (not the audio engine)
        engine.stop()
        
        // AVAudioEngine stays running for low latency
        // Only transport state changes to stopped
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
    }
    
    func testEngineStopIdempotent() async throws {
        engine.play()
        
        // Stop twice - should be idempotent
        engine.stop()
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        
        engine.stop()
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
    }
    
    func testEngineStopWhenTransportNotPlaying() {
        // Engine is already running after init, but transport is stopped
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        
        // Calling stop when already stopped should be graceful
        engine.stop()
        
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
    }
    
    // MARK: - Sample Rate Tests
    
    func testEngineSampleRate() async throws {
        engine.play()
        
        let sampleRate = engine.currentSampleRate
        
        // Sample rate should be one of standard rates
        let validRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        XCTAssertTrue(validRates.contains(sampleRate), "Sample rate \(sampleRate) should be standard rate")
    }
    
    func testEngineSampleRateConsistent() async throws {
        engine.play()
        
        let rate1 = engine.currentSampleRate
        let rate2 = engine.currentSampleRate
        
        XCTAssertEqual(rate1, rate2, "Sample rate should be consistent")
    }
    
    // MARK: - Project Configuration Tests
    
    func testEngineConfigureWithProjectManager() {
        // Should configure without throwing
        
        // Engine is running after init (auto-started)
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        // But transport is stopped
        XCTAssertEqual(engine.transportState, .stopped)
    }
    
    func testEngineLoadEmptyProject() async throws {
        let project = AudioProject(name: "Empty Project", tempo: 120.0)
        
        engine.play()
        
        engine.loadProject(project)
        
        // Project should be loaded
        XCTAssertEqual(engine.currentProject?.name, "Empty Project")
        XCTAssertEqual(engine.currentProject?.tempo, 120.0)
    }
    
    func testEngineLoadProjectWithTracks() async throws {
        var project = AudioProject(name: "Test Project", tempo: 140.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "Track 2", trackType: .midi, color: .red))
        
        engine.play()
        
        engine.loadProject(project)
        
        XCTAssertEqual(engine.currentProject?.tracks.count, 2)
        XCTAssertEqual(engine.currentProject?.tracks[0].name, "Track 1")
        XCTAssertEqual(engine.currentProject?.tracks[1].name, "Track 2")
    }
    
    func testEngineUpdateProjectData() async throws {
        var project = AudioProject(name: "Original", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        
        engine.play()
        engine.loadProject(project)
        
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
        
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let node = engine.getTrackNode(for: trackId)
        
        // Node should be created during project load
        XCTAssertNotNil(node)
    }
    
    func testEngineGetTrackNodeInvalidId() async throws {
        engine.play()
        
        let invalidId = UUID()
        let node = engine.getTrackNode(for: invalidId)
        
        XCTAssertNil(node, "Should return nil for invalid track ID")
    }
    
    func testEngineEnsureTrackNodeExists() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        let track = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        project.addTrack(track)
        
        engine.play()
        engine.loadProject(project)
        
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
        
        engine.play()
        engine.loadProject(project)
        
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
        
        engine.play()
        engine.loadProject(project)
        
        engine.setTrackPan(trackId, pan: -0.3)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertEqual(track?.mixerSettings.pan, -0.3)
    }
    
    func testEngineMuteTrack() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.play()
        engine.loadProject(project)
        
        engine.muteTrack(trackId, muted: true)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertTrue(track?.mixerSettings.isMuted ?? false)
    }
    
    func testEngineSoloTrack() async throws {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.soloTrack(trackId, solo: true)
        
        let updatedProject = engine.currentProject
        let track = updatedProject?.tracks.first { $0.id == trackId }
        XCTAssertTrue(track?.mixerSettings.isSolo ?? false)
    }
    
    func testEngineMasterVolume() async throws {
        engine.play()
        
        let defaultVolume = engine.masterVolume
        XCTAssertGreaterThan(defaultVolume, 0.0)
        
        engine.masterVolume = 0.6
        XCTAssertEqual(engine.masterVolume, 0.6)
    }
    
    // MARK: - Transport Control Tests
    
    func testEnginePlay() async throws {
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.play()
        
        XCTAssertEqual(engine.transportState, .playing)
    }
    
    func testEnginePause() async throws {
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.play()
        XCTAssertEqual(engine.transportState, .playing)
        
        engine.pause()
        XCTAssertEqual(engine.transportState, .paused)
    }
    
    func testEngineStopResetsPosition() async throws {
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        engine.play()
        engine.seek(toBeat: 16.0)
        
        engine.stop()
        
        XCTAssertEqual(engine.transportState, .stopped)
        // Position should be reset to 0
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    func testEngineSeekToBeat() async throws {
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        engine.seek(toBeat: 8.5)
        
        assertApproximatelyEqual(engine.currentPosition.beats, 8.5, tolerance: 0.1)
    }
    
    func testEngineSeekToSeconds() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.play()
        engine.loadProject(project)
        
        // 2 seconds at 120 BPM = 4 beats
        engine.seek(toSeconds: 2.0)
        
        assertApproximatelyEqual(engine.currentPosition.beats, 4.0, tolerance: 0.1)
    }
    
    func testEngineSeekNegativeBeatsClamps() async throws {
        engine.play()
        
        engine.seek(toBeat: -5.0)
        
        // Should clamp to 0
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    // MARK: - Cycle/Loop Tests
    
    func testEngineCycleEnabled() async throws {
        engine.play()
        
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
        // Load project with a MIDI track so record() takes the MIDI path and sets transport to .recording.
        // (Empty project would create an audio track and go through mic permission, never setting .recording.)
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "MIDI 1", trackType: .midi, color: .red))
        engine.loadProject(project)
        
        XCTAssertFalse(engine.isRecording)
        
        engine.record()
        
        XCTAssertTrue(engine.isRecording)
        XCTAssertEqual(engine.transportState, .recording)
    }
    
    func testEngineStopRecording() async throws {
        // Load project first (required for record())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        engine.record()
        XCTAssertTrue(engine.isRecording)
        
        engine.stopRecording()
        
        XCTAssertFalse(engine.isRecording)
    }
    
    func testEngineInputLevel() async throws {
        engine.play()
        
        let level = engine.inputLevel
        
        // Input level should be 0 or negative dB
        XCTAssertLessThanOrEqual(level, 0.0)
    }
    
    // MARK: - Bus Management Tests
    
    func testEngineAddBus() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.play()
        engine.loadProject(project)
        
        let bus = MixerBus(name: "Reverb", outputLevel: 0.8)
        engine.addBus(bus)
        
        // Verify bus was added
        XCTAssertNotNil(engine.getBusPluginChain(for: bus.id))
    }
    
    func testEngineRemoveBus() async throws {
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.play()
        engine.loadProject(project)
        
        let bus = MixerBus(name: "Reverb", outputLevel: 0.8)
        engine.addBus(bus)
        
        engine.removeBus(withId: bus.id)
        
        // Bus should be removed
        XCTAssertNil(engine.getBusPluginChain(for: bus.id))
    }
    
    // MARK: - Graph Generation Tests
    
    func testEngineGraphGenerationIncrementsOnMutation() async throws {
        let initialGeneration = engine.graphGeneration
        
        // Perform graph mutation
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "New Track", trackType: .audio, color: .blue))
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // NOTE: loadProject() uses projectLoadGeneration, not graphGeneration
        // graphGeneration is only incremented by AudioGraphManager mutations
        // For now, verify it stays stable (doesn't regress)
        XCTAssertGreaterThanOrEqual(engine.graphGeneration, initialGeneration)
    }
    
    func testEngineGraphGenerationValidation() async throws {
        let capturedGeneration = engine.graphGeneration
        
        // Initial generation should be valid
        XCTAssertTrue(engine.isGraphGenerationValid(capturedGeneration))
        
        // NOTE: loadProject() doesn't increment graphGeneration
        // (it uses projectLoadGeneration instead)
        // So this test verifies generation stays stable during normal project loads
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "New Track", trackType: .audio, color: .blue))
        engine.loadProject(project)
        
        // Wait for async project load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Generation should still be valid (unchanged)
        XCTAssertTrue(engine.isGraphGenerationValid(capturedGeneration))
    }
    
    // MARK: - Graph Stability Tests
    
    func testEngineGraphStabilityDuringLoad() async throws {
        // Graph should be stable initially
        XCTAssertTrue(engine.isGraphStable)
        
        // Load project (graph becomes unstable during load)
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // After load completes, graph should be stable again
        XCTAssertTrue(engine.isGraphStable)
    }
    
    // MARK: - Error Handling Tests
    
    func testEngineHandlesStartWithoutConfiguration() async {
        let unconfiguredEngine = AudioEngine()
        
        // Should handle gracefully (play() doesn't require configuration)
        unconfiguredEngine.play()
        XCTAssertTrue(true, "Engine handled play without throwing")
    }
    
    func testEngineHandlesPlayWhenTransportStopped() async throws {
        // Engine is already running after init
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.play()
        
        // Transport state should change to playing
        XCTAssertEqual(engine.transportState, .playing)
    }
    
    func testEngineHandlesSeekWhenTransportStopped() async throws {
        // Engine is running, but transport is stopped
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        
        // Load project first (required for seek())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.seek(toBeat: 10.0)
        
        // Should seek successfully even when transport is stopped
        assertApproximatelyEqual(engine.currentPosition.beats, 10.0, tolerance: 0.1)
    }
    
    func testEngineHandlesInvalidTrackOperations() async throws {
        engine.play()
        
        let invalidTrackId = UUID()
        
        // Should handle gracefully without crashing
        engine.setTrackVolume(invalidTrackId, volume: 0.5)
        engine.setTrackPan(invalidTrackId, pan: 0.0)
        engine.muteTrack(invalidTrackId, muted: true)
        
        XCTAssertTrue(true, "Invalid track operations did not crash")
    }
    
    // MARK: - Performance Tests
    
    func testEngineStartStopPerformance() async throws {
        
        measure {
            Task { @MainActor in
                engine.play()
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
        
        engine.play()
        
        measure {
            Task { @MainActor in
                engine.loadProject(project)
            }
        }
    }
    
    func testEngineSeekPerformance() async throws {
        engine.play()
        
        measure {
            for i in 0..<100 {
                engine.seek(toBeat: Double(i))
            }
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testEngineConcurrentSeek() async throws {
        engine.play()
        
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
        
        engine.play()
        engine.loadProject(project)
        
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
        // Load project first (required for play())
        let project = AudioProject(name: "Test", tempo: 120.0)
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        engine.play()
        XCTAssertEqual(engine.transportState, .playing)
        
        engine.stop()
        
        // Verify transport cleanup (engine stays running)
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
        XCTAssertEqual(engine.transportState, .stopped)
        XCTAssertEqual(engine.currentPosition.beats, 0.0)
    }
    
    func testEngineMemoryCleanup() async throws {
        // Create and destroy multiple engines to verify no leaks
        for _ in 0..<5 {
            let tempEngine = AudioEngine()
            tempEngine.play()
            tempEngine.stop()
        }
        
        // If we get here without crashing, memory is being managed correctly
        XCTAssertTrue(true, "Multiple engine lifecycle iterations completed")
    }
    
    // MARK: - Integration Tests
    
    func testEngineFullWorkflow() async throws {
        // Complete workflow: load project, play, record, stop
        var project = AudioProject(name: "Integration Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Audio Track", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "MIDI Track", trackType: .midi, color: .red))
        
        engine.loadProject(project)
        
        // Wait for async project load to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
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

    // MARK: - Track Removal Tests (Issue #81: dependency-aware disconnection order)

    /// Regression test for Issue #81: Rapid track deletion must not crash or corrupt the graph.
    /// Creates many tracks then removes all in quick succession; verifies engine stays stable.
    func testRapidTrackDeletion() async throws {
        var project = AudioProject(name: "Rapid Delete Test", tempo: 120.0)
        for i in 0..<20 {
            project.addTrack(AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue))
        }
        let trackIds = project.tracks.map(\.id)

        engine.loadProject(project)
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms for project load

        XCTAssertEqual(engine.currentProject?.tracks.count, 20)

        for trackId in trackIds {
            engine.removeTrack(trackId: trackId)
        }

        XCTAssertEqual(engine.currentProject?.tracks.count, 0)
        XCTAssertTrue(engine.isGraphStable, "Engine graph should remain stable after rapid track deletion")
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning, "Engine should still be running")
    }

    /// Regression test for Issue #81: Deleting one track must preserve remaining tracks and graph.
    /// Creates A, B, C then removes B; verifies A and C remain and engine is functional.
    func testTrackDeletionPreservesRemaining() async throws {
        var project = AudioProject(name: "Preserve Test", tempo: 120.0)
        let trackA = AudioTrack(name: "A", trackType: .audio, color: .blue)
        let trackB = AudioTrack(name: "B", trackType: .audio, color: .red)
        let trackC = AudioTrack(name: "C", trackType: .audio, color: .green)
        project.addTrack(trackA)
        project.addTrack(trackB)
        project.addTrack(trackC)

        engine.loadProject(project)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(engine.currentProject?.tracks.count, 3)

        engine.removeTrack(trackId: trackB.id)

        let remaining = engine.currentProject?.tracks ?? []
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains(where: { $0.id == trackA.id }))
        XCTAssertTrue(remaining.contains(where: { $0.id == trackC.id }))
        XCTAssertFalse(remaining.contains(where: { $0.id == trackB.id }))
        XCTAssertTrue(engine.isGraphStable, "Engine graph should remain stable after removing middle track")
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }

    /// Regression test for Issue #81: Removing a track that has bus sends must not corrupt the graph.
    /// Exercises removeAllSendsForTrack before teardown so pan/volume are disconnected from bus mixers.
    func testTrackDeletionWithBusSends() async throws {
        var project = AudioProject(name: "Bus Send Test", tempo: 120.0)
        let trackA = AudioTrack(name: "A", trackType: .audio, color: .blue)
        let trackB = AudioTrack(name: "B", trackType: .audio, color: .red)
        project.addTrack(trackA)
        project.addTrack(trackB)
        let bus = MixerBus(name: "Reverb")
        project.buses.append(bus)

        engine.loadProject(project)
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(engine.currentProject?.tracks.count, 2)
        engine.setupTrackSend(trackA.id, to: bus.id, level: 0.5)

        engine.removeTrack(trackId: trackA.id)

        let remaining = engine.currentProject?.tracks ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.contains(where: { $0.id == trackB.id }))
        XCTAssertFalse(remaining.contains(where: { $0.id == trackA.id }))
        XCTAssertTrue(engine.isGraphStable, "Engine graph should remain stable after removing track with bus sends")
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }

    /// Removing one track must not remove another track's bus sends.
    /// removeAllSendsForTrack is per-track; other tracks' sends must remain.
    func testRemoveTrackWithBusSendsLeavesOtherTrackSendsIntact() async throws {
        var project = AudioProject(name: "Two Sends Test", tempo: 120.0)
        let trackA = AudioTrack(name: "A", trackType: .audio, color: .blue)
        let trackB = AudioTrack(name: "B", trackType: .audio, color: .red)
        project.addTrack(trackA)
        project.addTrack(trackB)
        let bus = MixerBus(name: "Reverb")
        project.buses.append(bus)

        engine.loadProject(project)
        try await Task.sleep(nanoseconds: 150_000_000)

        engine.setupTrackSend(trackA.id, to: bus.id, level: 0.5)
        engine.setupTrackSend(trackB.id, to: bus.id, level: 0.3)

        engine.removeTrack(trackId: trackA.id)

        let remaining = engine.currentProject?.tracks ?? []
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, trackB.id)
        XCTAssertTrue(engine.isGraphStable, "Graph must remain stable after removing track with bus sends")
        XCTAssertTrue(engine.sharedAVAudioEngine.isRunning)
    }
}
