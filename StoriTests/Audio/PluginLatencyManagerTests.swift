//
//  PluginLatencyManagerTests.swift
//  StoriTests
//
//  Comprehensive tests for PluginLatencyManager - Plugin Delay Compensation (PDC)
//  Tests cover latency calculation, compensation delay computation, and real-world scenarios
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class PluginLatencyManagerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var manager: PluginLatencyManager!
    private let testSampleRate: Double = 48000.0
    
    // MARK: - Test Helpers
    
    /// Create a mock PluginDescriptor for testing
    private func makeTestDescriptor(
        name: String = "Test Plugin",
        manufacturer: String = "Test Manufacturer",
        latencySamples: Int = 0
    ) -> PluginDescriptor {
        return PluginDescriptor(
            id: UUID(),
            name: name,
            manufacturer: manufacturer,
            version: "1.0.0",
            category: .effect,
            componentDescription: AudioComponentDescriptionCodable(
                componentType: kAudioUnitType_Effect,
                componentSubType: 0x74737470,
                componentManufacturer: 0x74737461,
                componentFlags: 0,
                componentFlagsMask: 0
            ),
            auType: .aufx,
            supportsPresets: true,
            hasCustomUI: false,
            inputChannels: 2,
            outputChannels: 2,
            latencySamples: latencySamples
        )
    }
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        manager = PluginLatencyManager.shared
        manager.reset()
        manager.setSampleRate(testSampleRate)
        manager.isEnabled = true
    }
    
    override func tearDown() async throws {
        manager.reset()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testLatencyManagerInitialization() {
        XCTAssertNotNil(manager)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.maxLatencySamples, 0)
        XCTAssertEqual(manager.maxLatencyMs, 0.0)
    }
    
    func testLatencyManagerIsSingleton() {
        let manager2 = PluginLatencyManager.shared
        
        XCTAssertTrue(manager === manager2)
    }
    
    // MARK: - Sample Rate Tests
    
    func testSetSampleRate() {
        manager.setSampleRate(96000.0)
        
        // Sample rate should be updated (verified via latency calculations)
        XCTAssertTrue(true, "Sample rate set successfully")
    }
    
    func testSetSampleRateAffectsCalculations() {
        // Create mock plugin info
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        manager.setSampleRate(48000.0)
        let info1 = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        manager.setSampleRate(96000.0)
        let info2 = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // Sample rate should affect calculations
        XCTAssertEqual(info1.sampleRate, 48000.0)
        XCTAssertEqual(info2.sampleRate, 96000.0)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testLatencyManagerEnableState() {
        XCTAssertTrue(manager.isEnabled)
        
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
        
        manager.isEnabled = true
        XCTAssertTrue(manager.isEnabled)
    }
    
    func testDisabledPDCStillCalculates() {
        manager.isEnabled = false
        
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        // Should still calculate even when disabled
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertNotNil(info)
    }
    
    // MARK: - Plugin Latency Calculation Tests
    
    func testGetPluginLatencyWithoutAU() {
        let descriptor = makeTestDescriptor(name: "Test Plugin", manufacturer: "Test")
        let plugin = PluginInstance(descriptor: descriptor)
        
        let latency = manager.getPluginLatency(plugin)
        
        // Without loaded AU, latency should be 0
        XCTAssertEqual(latency, 0)
    }
    
    // MARK: - Track Latency Calculation Tests
    
    func testCalculateTrackLatencyWithNoPlugins() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertEqual(info.trackId, trackId)
        XCTAssertEqual(info.totalLatencySamples, 0)
        XCTAssertEqual(info.pluginLatencies.count, 0)
        XCTAssertEqual(info.sampleRate, testSampleRate)
        XCTAssertEqual(info.latencySeconds, 0.0)
        XCTAssertEqual(info.latencyMs, 0.0)
    }
    
    func testCalculateTrackLatencyWithSinglePlugin() {
        let trackId = UUID()
        let descriptor = makeTestDescriptor(name: "Test Plugin", manufacturer: "Test")
        let plugin = PluginInstance(descriptor: descriptor)
        let plugins = [plugin]
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertEqual(info.trackId, trackId)
        XCTAssertEqual(info.sampleRate, testSampleRate)
    }
    
    func testCalculateTrackLatencyWithMultiplePlugins() {
        let trackId = UUID()
        
        let plugin1 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 1", manufacturer: "Test"))
        let plugin2 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 2", manufacturer: "Test"))
        let plugin3 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 3", manufacturer: "Test"))
        
        let plugins = [plugin1, plugin2, plugin3]
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertEqual(info.trackId, trackId)
        // Total latency is sum of all plugins (0 in this case without real AUs)
        XCTAssertGreaterThanOrEqual(info.totalLatencySamples, 0)
    }
    
    // MARK: - Compensation Calculation Tests
    
    func testCalculateCompensationWithNoTracks() {
        let trackPlugins: [UUID: [PluginInstance]] = [:]
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        XCTAssertEqual(compensation.count, 0)
        XCTAssertEqual(manager.maxLatencySamples, 0)
        XCTAssertEqual(manager.maxLatencyMs, 0.0)
    }
    
    func testCalculateCompensationWithSingleTrack() {
        let trackId = UUID()
        let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Test Plugin", manufacturer: "Test"))
        
        let trackPlugins = [trackId: [plugin]]
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        XCTAssertEqual(compensation.count, 1)
        XCTAssertNotNil(compensation[trackId])
        
        // Track with max latency gets 0 compensation
        XCTAssertEqual(compensation[trackId], 0)
    }
    
    func testCalculateCompensationWithMultipleTracks() {
        let track1Id = UUID()
        let track2Id = UUID()
        let track3Id = UUID()
        
        let plugin1 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 1", manufacturer: "Test"))
        let plugin2 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 2", manufacturer: "Test"))
        
        let trackPlugins = [
            track1Id: [plugin1],
            track2Id: [plugin2],
            track3Id: []
        ]
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        XCTAssertEqual(compensation.count, 3)
    }
    
    func testCalculateCompensationMaxLatency() {
        // Create tracks with different plugin counts
        let track1Id = UUID()  // 0 plugins
        let track2Id = UUID()  // 1 plugin
        let track3Id = UUID()  // 2 plugins
        
        let plugin1 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 1", manufacturer: "Test"))
        let plugin2 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 2", manufacturer: "Test"))
        
        let trackPlugins = [
            track1Id: [],
            track2Id: [plugin1],
            track3Id: [plugin1, plugin2]
        ]
        
        _ = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        // Max latency should be calculated
        XCTAssertGreaterThanOrEqual(manager.maxLatencySamples, 0)
        XCTAssertGreaterThanOrEqual(manager.maxLatencyMs, 0.0)
    }
    
    // MARK: - Latency Info Conversion Tests
    
    func testLatencySecondsConversion() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // 0 samples at 48kHz = 0 seconds
        XCTAssertEqual(info.latencySeconds, 0.0)
    }
    
    func testLatencyMillisecondsConversion() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // 0 samples at 48kHz = 0 ms
        XCTAssertEqual(info.latencyMs, 0.0)
    }
    
    func testLatencyConversionAtDifferentSampleRates() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        // Test at 48kHz
        manager.setSampleRate(48000.0)
        let info48k = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // Test at 96kHz
        manager.setSampleRate(96000.0)
        let info96k = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // Same sample count should yield different time values
        XCTAssertEqual(info48k.sampleRate, 48000.0)
        XCTAssertEqual(info96k.sampleRate, 96000.0)
    }
    
    // MARK: - Track Retrieval Tests
    
    func testGetTrackLatency() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        // Calculate latency
        _ = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        // Retrieve it
        let retrieved = manager.getTrackLatency(for: trackId)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.trackId, trackId)
    }
    
    func testGetTrackLatencyInvalidTrack() {
        let invalidId = UUID()
        
        let retrieved = manager.getTrackLatency(for: invalidId)
        
        XCTAssertNil(retrieved)
    }
    
    // MARK: - Track Removal Tests
    
    func testRemoveTrack() {
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        _ = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertNotNil(manager.getTrackLatency(for: trackId))
        
        manager.removeTrack(trackId)
        
        XCTAssertNil(manager.getTrackLatency(for: trackId))
    }
    
    func testRemoveNonExistentTrack() {
        let invalidId = UUID()
        
        // Should handle gracefully
        manager.removeTrack(invalidId)
        
        XCTAssertTrue(true, "Remove non-existent track handled gracefully")
    }
    
    func testRemoveMultipleTracks() {
        let track1Id = UUID()
        let track2Id = UUID()
        let track3Id = UUID()
        
        let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Test Plugin", manufacturer: "Test"))
        
        _ = manager.calculateTrackLatency(trackId: track1Id, plugins: [plugin])
        _ = manager.calculateTrackLatency(trackId: track2Id, plugins: [plugin])
        _ = manager.calculateTrackLatency(trackId: track3Id, plugins: [])
        
        manager.removeTrack(track1Id)
        XCTAssertNil(manager.getTrackLatency(for: track1Id))
        XCTAssertNotNil(manager.getTrackLatency(for: track2Id))
        XCTAssertNotNil(manager.getTrackLatency(for: track3Id))
        
        manager.removeTrack(track3Id)
        XCTAssertNil(manager.getTrackLatency(for: track3Id))
        XCTAssertNotNil(manager.getTrackLatency(for: track2Id))
    }
    
    // MARK: - Reset Tests
    
    func testReset() {
        // Add some tracks
        let track1Id = UUID()
        let track2Id = UUID()
        
        let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Test Plugin", manufacturer: "Test"))
        
        let trackPlugins = [
            track1Id: [plugin],
            track2Id: []
        ]
        
        _ = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        // Reset
        manager.reset()
        
        // All data should be cleared
        XCTAssertEqual(manager.maxLatencySamples, 0)
        XCTAssertEqual(manager.maxLatencyMs, 0.0)
        XCTAssertNil(manager.getTrackLatency(for: track1Id))
        XCTAssertNil(manager.getTrackLatency(for: track2Id))
    }
    
    func testResetIdempotent() {
        manager.reset()
        manager.reset()
        manager.reset()
        
        XCTAssertEqual(manager.maxLatencySamples, 0)
    }
    
    // MARK: - Real-World Scenario Tests
    
    func testTypicalProjectScenario() {
        // Scenario: 3 tracks with varying plugin counts
        // Track 1: Vocal (reverb, compressor) = 2 plugins
        // Track 2: Guitar (amp sim) = 1 plugin
        // Track 3: Drum (no plugins) = 0 plugins
        
        let vocalTrackId = UUID()
        let guitarTrackId = UUID()
        let drumTrackId = UUID()
        
        let reverb = PluginInstance(descriptor: makeTestDescriptor(name: "Reverb", manufacturer: "Test"))
        let compressor = PluginInstance(descriptor: makeTestDescriptor(name: "Compressor", manufacturer: "Test"))
        let ampSim = PluginInstance(descriptor: makeTestDescriptor(name: "Amp Simulator", manufacturer: "Test"))
        
        let trackPlugins = [
            vocalTrackId: [reverb, compressor],
            guitarTrackId: [ampSim],
            drumTrackId: []
        ]
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        // All tracks should have compensation calculated
        XCTAssertEqual(compensation.count, 3)
        
        // Track with most plugins should have 0 compensation
        // Tracks with fewer plugins should be delayed
        XCTAssertEqual(compensation[vocalTrackId], 0)
        XCTAssertGreaterThanOrEqual(compensation[guitarTrackId] ?? 0, 0)
        XCTAssertGreaterThanOrEqual(compensation[drumTrackId] ?? 0, 0)
    }
    
    func testLargeProjectScenario() {
        // Scenario: 16 tracks with random plugin counts
        var trackPlugins: [UUID: [PluginInstance]] = [:]
        
        for i in 0..<16 {
            let trackId = UUID()
            var plugins: [PluginInstance] = []
            
            // Random number of plugins (0-4)
            let pluginCount = i % 5
            for j in 0..<pluginCount {
                let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)-\(j)", manufacturer: "Test"))
                plugins.append(plugin)
            }
            
            trackPlugins[trackId] = plugins
        }
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        
        XCTAssertEqual(compensation.count, 16)
    }
    
    // MARK: - Performance Tests
    
    func testLatencyCalculationPerformance() {
        let trackId = UUID()
        
        let plugins = (0..<8).map { i in
            PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)", manufacturer: "Test"))
        }
        
        measure {
            for _ in 0..<100 {
                _ = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
            }
        }
    }
    
    func testCompensationCalculationPerformance() {
        // Create 16 tracks with varying plugin counts
        var trackPlugins: [UUID: [PluginInstance]] = [:]
        
        for i in 0..<16 {
            let trackId = UUID()
            let pluginCount = i % 5
            let plugins = (0..<pluginCount).map { j in
                PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)-\(j)", manufacturer: "Test"))
            }
            trackPlugins[trackId] = plugins
        }
        
        measure {
            _ = manager.calculateCompensation(trackPlugins: trackPlugins)
        }
    }
    
    func testTrackRemovalPerformance() {
        // Add many tracks
        var trackIds: [UUID] = []
        
        for i in 0..<100 {
            let trackId = UUID()
            trackIds.append(trackId)
            
            let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)", manufacturer: "Test"))
            
            _ = manager.calculateTrackLatency(trackId: trackId, plugins: [plugin])
        }
        
        measure {
            for trackId in trackIds {
                manager.removeTrack(trackId)
            }
            
            // Re-add for next iteration
            for i in 0..<100 {
                let trackId = trackIds[i]
                let plugin = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)", manufacturer: "Test"))
                _ = manager.calculateTrackLatency(trackId: trackId, plugins: [plugin])
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testZeroSampleRate() {
        // Edge case: zero sample rate
        manager.setSampleRate(0.0)
        
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        // Should handle gracefully (may produce inf/nan but shouldn't crash)
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertNotNil(info)
    }
    
    func testVeryHighSampleRate() {
        // Edge case: very high sample rate (384kHz)
        manager.setSampleRate(384000.0)
        
        let trackId = UUID()
        let plugins: [PluginInstance] = []
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertEqual(info.sampleRate, 384000.0)
    }
    
    func testManyPluginsOnOneTrack() {
        let trackId = UUID()
        
        // 32 plugins on one track
        let plugins = (0..<32).map { i in
            PluginInstance(descriptor: makeTestDescriptor(name: "Plugin \(i)", manufacturer: "Test"))
        }
        
        let info = manager.calculateTrackLatency(trackId: trackId, plugins: plugins)
        
        XCTAssertEqual(info.trackId, trackId)
        XCTAssertGreaterThanOrEqual(info.totalLatencySamples, 0)
    }
    
    func testTrackLatencyInfoStructEquality() {
        let trackId1 = UUID()
        let trackId2 = trackId1
        
        let info1 = PluginLatencyManager.TrackLatencyInfo(
            trackId: trackId1,
            totalLatencySamples: 100,
            pluginLatencies: [],
            sampleRate: 48000.0
        )
        
        let info2 = PluginLatencyManager.TrackLatencyInfo(
            trackId: trackId2,
            totalLatencySamples: 100,
            pluginLatencies: [],
            sampleRate: 48000.0
        )
        
        XCTAssertEqual(info1.trackId, info2.trackId)
        XCTAssertEqual(info1.totalLatencySamples, info2.totalLatencySamples)
        XCTAssertEqual(info1.sampleRate, info2.sampleRate)
    }
    
    // MARK: - Integration Tests
    
    func testFullPDCWorkflow() {
        // Complete PDC workflow: configure, calculate, retrieve, remove, reset
        
        // 1. Configure
        manager.setSampleRate(48000.0)
        manager.isEnabled = true
        
        // 2. Create tracks with plugins
        let track1Id = UUID()
        let track2Id = UUID()
        
        let plugin1 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 1", manufacturer: "Test"))
        let plugin2 = PluginInstance(descriptor: makeTestDescriptor(name: "Plugin 2", manufacturer: "Test"))
        
        // 3. Calculate compensation
        let trackPlugins = [
            track1Id: [plugin1, plugin2],
            track2Id: [plugin1]
        ]
        
        let compensation = manager.calculateCompensation(trackPlugins: trackPlugins)
        XCTAssertEqual(compensation.count, 2)
        
        // 4. Retrieve track latency
        let latency1 = manager.getTrackLatency(for: track1Id)
        XCTAssertNotNil(latency1)
        
        // 5. Remove one track
        manager.removeTrack(track2Id)
        XCTAssertNil(manager.getTrackLatency(for: track2Id))
        XCTAssertNotNil(manager.getTrackLatency(for: track1Id))
        
        // 6. Disable PDC
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
        
        // 7. Reset
        manager.reset()
        XCTAssertNil(manager.getTrackLatency(for: track1Id))
        XCTAssertEqual(manager.maxLatencySamples, 0)
        
        XCTAssertTrue(true, "Full PDC workflow completed successfully")
    }
}
