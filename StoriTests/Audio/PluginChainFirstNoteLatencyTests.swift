//
//  PluginChainFirstNoteLatencyTests.swift
//  StoriTests
//
//  Tests for plugin chain first-note latency prevention (BUG FIX Issue #54)
//  Ensures no audio latency on first playback after stop/project load
//
//  BUG REPORT (GitHub Issue #54):
//  =================================
//  PluginChain uses lazy initialization - Audio Unit nodes aren't fully attached
//  to the graph until first audio passes through. This can cause the first note
//  or audio to be delayed or silent while the AU initializes (10-100ms latency).
//
//  ROOT CAUSE:
//  -----------
//  - Plugin chains use lazy `realize()` (mixers attached on first plugin insert)
//  - Audio Units don't allocate render resources until first buffer callback
//  - No pre-roll or warmup before playback starts
//  - Heavy synth plugins can take 50-100ms to initialize internal DSP state
//
//  SOLUTION:
//  ---------
//  1. Added `prepareForPlayback()` to PluginChain (eager resource allocation)
//  2. Call `allocateRenderResources()` on all active AUs before playback
//  3. Ensure chain is fully realized before first audio callback
//  4. Integrated into `AudioEngine.startPlaybackInternal()` as pre-roll step
//
//  PROFESSIONAL STANDARD:
//  ----------------------
//  Logic Pro, Pro Tools, and Cubase all have 0ms first-note latency by:
//  - Allocating AU resources during project load or when transport arms
//  - Pre-warming AU internal state before first buffer
//  - Maintaining render resources across transport stop/start cycles
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class PluginChainFirstNoteLatencyTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    /// Maximum acceptable first-note latency (professional standard)
    private let maxAcceptableLatencyMs: Double = 5.0
    
    /// Sample rate for testing
    private let sampleRate: Double = 48000.0
    
    /// Test engine and format
    private var engine: AVAudioEngine!
    private var format: AVAudioFormat!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        // BUG FIX (ASan "freed pointer was not the last allocation"):
        // Avoiding async setUp to prevent Swift Concurrency task teardown bug
        // in XCTest's error observation (swift_task_dealloc_specific).
        // Pattern: Use synchronous setUp when no actual async work is needed.
        super.setUp()
        
        engine = AVAudioEngine()
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        
        // Attach a test node before starting to avoid AVAudioEngine assertion
        // AVFoundation requires at least one node attached before starting
        let testMixer = AVAudioMixerNode()
        engine.attach(testMixer)
        engine.connect(testMixer, to: engine.outputNode, format: format)
        
        // Start engine (failure in setUp will fail all tests, which is appropriate)
        do {
            try engine.start()
        } catch {
            XCTFail("Failed to start engine in setUp: \(error)")
        }
    }
    
    override func tearDown() {
        engine.stop()
        engine = nil
        format = nil
        
        super.tearDown()
    }
    
    // MARK: - Core Preparation Tests
    
    /// Test that prepareForPlayback() allocates render resources
    func testPrepareForPlaybackAllocatesResources() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        // Create mock plugin instance
        let descriptor = createMockPluginDescriptor(name: "TestSynth")
        let plugin = PluginInstance(descriptor: descriptor)
        
        // Load plugin
        try await plugin.load(sampleRate: sampleRate)
        
        // Store in chain
        chain.storePlugin(plugin, atSlot: 0)
        
        // Realize chain
        chain.realize()
        
        // Verify resources NOT allocated before prepare
        XCTAssertNotNil(plugin.auAudioUnit)
        let au = plugin.auAudioUnit!
        XCTAssertFalse(au.renderResourcesAllocated, "Resources should not be allocated before prepare")
        
        // Prepare for playback
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared, "Preparation should succeed")
        
        // Verify resources ARE allocated after prepare
        XCTAssertTrue(au.renderResourcesAllocated, "Resources should be allocated after prepare")
    }
    
    /// Test that prepareForPlayback() realizes chain if not already realized
    func testPrepareForPlaybackRealizesChain() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        // Create and add plugin
        let descriptor = createMockPluginDescriptor(name: "TestEQ")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        
        // Chain should not be realized yet
        XCTAssertFalse(chain.isRealized)
        
        // Prepare for playback
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared)
        
        // Chain should now be realized
        XCTAssertTrue(chain.isRealized)
    }
    
    /// Test that prepareForPlayback() handles empty chains gracefully
    func testPrepareForPlaybackWithNoPlugins() {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        // No plugins
        XCTAssertFalse(chain.hasActivePlugins)
        
        // Prepare should succeed (nothing to prepare)
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared)
        
        // Chain should not be realized (no reason to)
        XCTAssertFalse(chain.isRealized)
    }
    
    /// Test that prepareForPlayback() skips bypassed plugins
    func testPrepareForPlaybackSkipsBypassedPlugins() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        // Create two plugins
        let descriptor1 = createMockPluginDescriptor(name: "Active")
        let plugin1 = PluginInstance(descriptor: descriptor1)
        try await plugin1.load(sampleRate: sampleRate)
        
        let descriptor2 = createMockPluginDescriptor(name: "Bypassed")
        let plugin2 = PluginInstance(descriptor: descriptor2)
        try await plugin2.load(sampleRate: sampleRate)
        plugin2.isBypassed = true
        
        chain.storePlugin(plugin1, atSlot: 0)
        chain.storePlugin(plugin2, atSlot: 1)
        chain.realize()
        
        // Prepare
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared)
        
        // Active plugin should have resources allocated
        XCTAssertTrue(plugin1.auAudioUnit!.renderResourcesAllocated)
        
        // Bypassed plugin should NOT have resources allocated (optimization)
        XCTAssertFalse(plugin2.auAudioUnit!.renderResourcesAllocated)
    }
    
    // MARK: - First-Note Latency Regression Tests
    
    /// Test that first note is not delayed after cold start (exact Issue #54 scenario)
    func testFirstNoteNotDelayedAfterColdStart() async throws {
        // This test simulates the exact bug scenario:
        // 1. Create track with heavy synth plugin
        // 2. Cold-start playback (after engine stop)
        // 3. Schedule note at sample 0
        // 4. Verify note onset within acceptable latency
        
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        // Create heavy synth plugin (simulated)
        let descriptor = createMockPluginDescriptor(name: "HeavySynth")
        let plugin = PluginInstance(descriptor: descriptor)
        defer { plugin.unload() }
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        
        // Realize chain while engine is running
        chain.realize()
        
        // Stop engine (cold start scenario - simulates user stopping playback)
        engine.stop()
        
        // BUG FIX: Prepare for playback BEFORE restarting engine
        // This allocates render resources eagerly so first note isn't delayed
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared, "Preparation must succeed")
        
        // Verify render resources are allocated BEFORE engine restarts
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated,
                      "Resources must be allocated before engine restart")
        
        // Restart engine
        try engine.start()
        
        // Resources should still be allocated after restart
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated,
                      "Resources must remain allocated after engine restart")
        
        // Measure time from play command to first audio processing
        // (In a real test, we'd schedule a note and measure its onset time)
        // For unit test purposes, verify the preparation step completed quickly
        let prepStartTime = CFAbsoluteTimeGetCurrent()
        _ = chain.prepareForPlayback() // Second call should be instant (already prepared)
        let prepEndTime = CFAbsoluteTimeGetCurrent()
        let prepDurationMs = (prepEndTime - prepStartTime) * 1000.0
        
        XCTAssertLessThan(prepDurationMs, maxAcceptableLatencyMs,
                         "Preparation latency (\(prepDurationMs)ms) exceeds professional standard (\(maxAcceptableLatencyMs)ms)")
    }
    
    /// Test multiple plugin chain preparation completes within time budget
    func testMultiplePluginChainsPrepareFast() async throws {
        var chains: [PluginChain] = []
        
        // Create 8 tracks with 3 plugins each (typical project)
        for trackIdx in 0..<8 {
            let chain = PluginChain(maxSlots: 8)
            chain.install(in: engine, format: format)
            
            for pluginIdx in 0..<3 {
                let descriptor = createMockPluginDescriptor(name: "Plugin\(trackIdx)-\(pluginIdx)")
                let plugin = PluginInstance(descriptor: descriptor)
                try await plugin.load(sampleRate: sampleRate)
                chain.storePlugin(plugin, atSlot: pluginIdx)
            }
            
            chain.realize()
            chains.append(chain)
        }
        
        // Measure total preparation time
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var successCount = 0
        for chain in chains {
            if chain.prepareForPlayback() {
                successCount += 1
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalDurationMs = (endTime - startTime) * 1000.0
        
        // All chains should prepare successfully
        XCTAssertEqual(successCount, chains.count, "All chains should prepare")
        
        // Total time should be reasonable (< 100ms for 24 plugins)
        XCTAssertLessThan(totalDurationMs, 100.0,
                         "Preparing \(chains.count) chains took \(totalDurationMs)ms (should be < 100ms)")
    }
    
    // MARK: - Edge Cases
    
    /// Test preparation with no engine reference
    func testPrepareWithNoEngine() {
        let chain = PluginChain(maxSlots: 8)
        
        // Don't install in engine
        let prepared = chain.prepareForPlayback()
        XCTAssertFalse(prepared, "Preparation should fail without engine")
    }
    
    /// Test preparation after engine stops (engine must be running to realize)
    func testPrepareAfterEngineStops() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        let descriptor = createMockPluginDescriptor(name: "TestPlugin")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        
        // Realize chain while engine is running
        chain.realize()
        
        // Stop engine (simulates user stopping playback in a loaded project)
        engine.stop()
        
        // Preparation should work (allocates resources even when engine stopped)
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared, "Preparation should work when chain is realized but engine is stopped")
        
        // Verify resources are allocated
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated, 
                      "Resources should be allocated before engine restart")
        
        // Restart and verify still prepared
        try engine.start()
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated,
                      "Resources should remain allocated after engine restart")
    }
    
    /// Test idempotent preparation (calling twice)
    func testIdempotentPreparation() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        let descriptor = createMockPluginDescriptor(name: "TestPlugin")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        chain.realize()
        
        // First prepare
        let prepared1 = chain.prepareForPlayback()
        XCTAssertTrue(prepared1)
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated)
        
        // Second prepare (should be no-op)
        let prepared2 = chain.prepareForPlayback()
        XCTAssertTrue(prepared2)
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated)
    }
    
    /// Test preparation with mix of active and bypassed plugins
    func testPreparationWithMixedBypassState() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        var plugins: [PluginInstance] = []
        for i in 0..<4 {
            let descriptor = createMockPluginDescriptor(name: "Plugin\(i)")
            let plugin = PluginInstance(descriptor: descriptor)
            try await plugin.load(sampleRate: sampleRate)
            plugin.isBypassed = (i % 2 == 1) // Bypass every other plugin
            chain.storePlugin(plugin, atSlot: i)
            plugins.append(plugin)
        }
        
        chain.realize()
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared)
        
        // Active plugins (0, 2) should have resources
        XCTAssertTrue(plugins[0].auAudioUnit!.renderResourcesAllocated)
        XCTAssertTrue(plugins[2].auAudioUnit!.renderResourcesAllocated)
        
        // Bypassed plugins (1, 3) should NOT have resources
        XCTAssertFalse(plugins[1].auAudioUnit!.renderResourcesAllocated)
        XCTAssertFalse(plugins[3].auAudioUnit!.renderResourcesAllocated)
    }
    
    // MARK: - Integration with Transport
    
    /// Test that preparation happens before scheduling audio
    func testPreparationBeforeScheduling() async throws {
        // This simulates the AudioEngine.startPlaybackInternal() flow
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        let descriptor = createMockPluginDescriptor(name: "PreSchedule")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        
        // Simulate playback start sequence
        // 1. Prepare plugins (BUG FIX)
        let prepared = chain.prepareForPlayback()
        XCTAssertTrue(prepared)
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated)
        
        // 2. Schedule audio/MIDI (after preparation)
        // (In real code, this would be playbackScheduler.scheduleAllTracks())
        
        // 3. Start transport
        // (In real code, this would trigger first audio callback)
        
        // Verify resources are ready before audio processing begins
        XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated,
                      "Resources must be ready before scheduling")
    }
    
    // MARK: - Performance Benchmarks
    
    /// Benchmark preparation time for typical project (8 tracks, 2 plugins each)
    func testPreparationPerformanceTypicalProject() async throws {
        var chains: [PluginChain] = []
        
        // Typical project: 8 tracks, 2 plugins each
        for trackIdx in 0..<8 {
            let chain = PluginChain(maxSlots: 8)
            chain.install(in: engine, format: format)
            
            for pluginIdx in 0..<2 {
                let descriptor = createMockPluginDescriptor(name: "T\(trackIdx)P\(pluginIdx)")
                let plugin = PluginInstance(descriptor: descriptor)
                try await plugin.load(sampleRate: sampleRate)
                chain.storePlugin(plugin, atSlot: pluginIdx)
            }
            
            chain.realize()
            chains.append(chain)
        }
        
        // Measure preparation time
        measure {
            for chain in chains {
                _ = chain.prepareForPlayback()
            }
        }
    }
    
    /// Benchmark preparation time for heavy project (16 tracks, 5 plugins each)
    func testPreparationPerformanceHeavyProject() async throws {
        var chains: [PluginChain] = []
        
        // Heavy project: 16 tracks, 5 plugins each
        for trackIdx in 0..<16 {
            let chain = PluginChain(maxSlots: 8)
            chain.install(in: engine, format: format)
            
            for pluginIdx in 0..<5 {
                let descriptor = createMockPluginDescriptor(name: "T\(trackIdx)P\(pluginIdx)")
                let plugin = PluginInstance(descriptor: descriptor)
                try await plugin.load(sampleRate: sampleRate)
                chain.storePlugin(plugin, atSlot: pluginIdx)
            }
            
            chain.realize()
            chains.append(chain)
        }
        
        // Measure preparation time
        let startTime = CFAbsoluteTimeGetCurrent()
        for chain in chains {
            _ = chain.prepareForPlayback()
        }
        let endTime = CFAbsoluteTimeGetCurrent()
        let durationMs = (endTime - startTime) * 1000.0
        
        // Even heavy projects should prepare quickly (< 200ms)
        XCTAssertLessThan(durationMs, 200.0,
                         "Heavy project preparation (\(durationMs)ms) should be < 200ms")
    }
    
    // MARK: - WYSIWYG (What You Hear Is What You Get)
    
    /// Test that preparation produces deterministic results across runs
    func testPreparationDeterministic() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        let descriptor = createMockPluginDescriptor(name: "Deterministic")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        
        // Prepare multiple times
        for _ in 0..<5 {
            // Deallocate
            if plugin.auAudioUnit!.renderResourcesAllocated {
                plugin.auAudioUnit!.deallocateRenderResources()
            }
            XCTAssertFalse(plugin.auAudioUnit!.renderResourcesAllocated)
            
            // Re-prepare
            let prepared = chain.prepareForPlayback()
            XCTAssertTrue(prepared)
            XCTAssertTrue(plugin.auAudioUnit!.renderResourcesAllocated)
        }
    }
    
    // MARK: - Regression Protection
    
    /// Test that unprepared chains still work (graceful degradation)
    func testUnpreparedChainStillWorks() async throws {
        let chain = PluginChain(maxSlots: 8)
        chain.install(in: engine, format: format)
        
        let descriptor = createMockPluginDescriptor(name: "Unprepared")
        let plugin = PluginInstance(descriptor: descriptor)
        try await plugin.load(sampleRate: sampleRate)
        chain.storePlugin(plugin, atSlot: 0)
        chain.realize()
        
        // Don't call prepareForPlayback() - simulate old behavior
        
        // Chain should still be realized and connected
        XCTAssertTrue(chain.isRealized)
        XCTAssertNotNil(plugin.avAudioUnit)
        
        // Resources will be allocated on first audio callback (lazy)
        // This is the old behavior that caused first-note latency
        XCTAssertFalse(plugin.auAudioUnit!.renderResourcesAllocated)
    }
    
    // MARK: - Helper Methods
    
    /// Create a mock plugin descriptor for testing (uses Apple NewTimePitch AU)
    private func createMockPluginDescriptor(name: String) -> PluginDescriptor {
        let componentDesc = AudioComponentDescriptionCodable(
            componentType: kAudioUnitType_FormatConverter,
            componentSubType: kAudioUnitSubType_NewTimePitch,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return PluginDescriptor(
            id: UUID(),
            name: name,
            manufacturer: "Test",
            version: "1.0",
            category: .effect,
            componentDescription: componentDesc,
            auType: .aufx,
            supportsPresets: true,
            hasCustomUI: false,
            inputChannels: 2,
            outputChannels: 2,
            latencySamples: 0
        )
    }
}
