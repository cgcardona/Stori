//
//  MIDIPlaybackEngine.swift
//  Stori
//
//  Handles MIDI playback scheduling and timing for MIDI regions on the timeline.
//  Uses sample-accurate scheduling with calculated future sample times.
//
//  Architecture: All timing is in BEATS. The scheduler calculates precise
//  sample times and schedules events via AUScheduleMIDIEventBlock.
//
//  SAMPLE-ACCURATE MIDI:
//  - MIDI blocks are cached for thread-safe access from the scheduler queue
//  - Events are scheduled with calculated sample offsets (not immediate)
//  - Uses AUScheduleMIDIEventBlock with future sample times for sub-sample accuracy
//

import Foundation
import AVFoundation
import Observation
import os.lock

// MARK: - MIDI Playback Engine

/// Engine for playing back MIDI regions in sync with the timeline.
/// Uses sample-accurate scheduling with calculated future sample times.
/// All timing is beats-based internally, converted to samples for AU scheduling.
@Observable
@MainActor
class MIDIPlaybackEngine {
    
    // MARK: - Sample-Accurate Scheduler
    
    /// The sample-accurate scheduler for professional-grade timing
    @ObservationIgnored
    private let scheduler = SampleAccurateMIDIScheduler()
    
    /// Public accessor for shared scheduler (used by metronome for timing synchronization)
    var sampleAccurateScheduler: SampleAccurateMIDIScheduler {
        scheduler
    }
    
    // MARK: - Thread-Safe MIDI Block Cache
    
    /// Lock for thread-safe access to MIDI blocks
    @ObservationIgnored
    private nonisolated(unsafe) var midiBlockLock = os_unfair_lock_s()
    
    /// Cached MIDI blocks for each track (thread-safe access)
    /// Key: trackId, Value: AUScheduleMIDIEventBlock
    @ObservationIgnored
    private nonisolated(unsafe) var midiBlocks: [UUID: AUScheduleMIDIEventBlock] = [:]
    
    /// Pre-allocated MIDI data buffer (3 bytes: status, data1, data2)
    /// Reused for every MIDI event to avoid allocation in hot path
    /// REAL-TIME SAFETY: Eliminates array allocation on every MIDI event
    @ObservationIgnored
    private nonisolated(unsafe) var midiDataBuffer: [UInt8] = [0, 0, 0]
    
    /// Atomic flag for tracking missing MIDI blocks (lock-free error detection)
    /// Bit flags: one bit per track (up to 64 tracks)
    @ObservationIgnored
    private nonisolated(unsafe) var missingBlockFlags: UInt64 = 0
    @ObservationIgnored
    private nonisolated(unsafe) var missingBlockFlagsLock = os_unfair_lock_s()
    
    // MARK: - Properties
    
    @ObservationIgnored
    private weak var instrumentManager: InstrumentManager?
    
    @ObservationIgnored
    private weak var audioEngine: AudioEngine?
    
    @ObservationIgnored
    private weak var transportController: TransportController?
    
    @ObservationIgnored
    private var tempo: Double = 120.0
    
    @ObservationIgnored
    private var sampleRate: Double = 48000.0
    
    /// Thread-safe current position in beats
    /// CRITICAL: Use atomic accessor from TransportController, not MainActor-isolated AudioEngine property
    @ObservationIgnored
    private var currentPositionBeats: Double {
        // Prefer atomic accessor for thread-safe, jitter-free position
        if let transport = transportController {
            return transport.atomicBeatPosition
        }
        // Fallback: MainActor-isolated read (NOT safe from audio thread!)
        return audioEngine?.currentPosition.beats ?? 0
    }
    
    // MARK: - Cycle Awareness
    
    @ObservationIgnored
    private var isCycleEnabled: Bool {
        audioEngine?.isCycleEnabled ?? false
    }
    
    @ObservationIgnored
    private var cycleStartBeat: Double {
        audioEngine?.cycleStartBeat ?? 0
    }
    
    @ObservationIgnored
    private var cycleEndBeat: Double {
        audioEngine?.cycleEndBeat ?? 4
    }
    
    @ObservationIgnored
    private(set) var isPlaying = false
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Configuration
    
    /// Configure the engine with dependencies
    func configure(with instrumentManager: InstrumentManager, audioEngine: AudioEngine) {
        self.instrumentManager = instrumentManager
        self.audioEngine = audioEngine
    }
    
    /// Configure sample-accurate scheduling with thread-safe beat provider
    /// Call this after the audio engine and transport are initialized
    func configureSampleAccurateScheduling(avEngine: AVAudioEngine, sampleRate: Double, transportController: TransportController? = nil) {
        self.transportController = transportController
        self.sampleRate = sampleRate
        
        // Configure scheduler with timing parameters
        scheduler.configure(tempo: tempo, sampleRate: sampleRate)
        
        // Set up thread-safe beat provider
        // Uses atomic accessor from TransportController (readable from any thread)
        if let transport = transportController {
            scheduler.currentBeatProvider = { [weak transport] in
                transport?.atomicBeatPosition ?? 0
            }
        } else {
            // Fallback: read from AudioEngine on main thread (less precise but works)
            scheduler.currentBeatProvider = { [weak self] in
                self?.currentPositionBeats ?? 0
            }
        }
        
        // Set up sample-accurate MIDI handler (the ONLY MIDI dispatch path)
        scheduler.sampleAccurateMIDIHandler = { [weak self] status, data1, data2, trackId, sampleTime in
            self?.dispatchMIDIWithSampleTime(
                status: status, data1: data1, data2: data2,
                trackId: trackId, sampleTime: sampleTime
            )
        }
    }
    
    // MARK: - Event Scheduling
    
    /// Load MIDI regions from tracks and schedule events (all beats-based)
    func loadRegions(from tracks: [AudioTrack], tempo: Double = 120.0) {
        self.tempo = tempo
        
        // Update scheduler timing parameters
        scheduler.configure(tempo: tempo, sampleRate: sampleRate)
        
        // Update cycle state
        scheduler.setCycle(
            enabled: isCycleEnabled,
            startBeat: cycleStartBeat,
            endBeat: cycleEndBeat
        )
        
        // Cache MIDI blocks for sample-accurate dispatch
        cacheMIDIBlocks(from: tracks)
        
        // Load events into scheduler
        scheduler.loadEvents(from: tracks)
    }
    
    // MARK: - Playback Control
    
    /// Start playback from a specific beat position
    func play(fromBeat startBeat: Double) {
        isPlaying = true
        
        // Update cycle state and start scheduler
        scheduler.setCycle(
            enabled: isCycleEnabled,
            startBeat: cycleStartBeat,
            endBeat: cycleEndBeat
        )
        scheduler.play(fromBeat: startBeat)
    }
    
    /// Stop playback and kill all active notes
    func stop() {
        // Stop scheduler FIRST (waits for in-flight events)
        scheduler.stop()
        
        // Then update state
        isPlaying = false
        
        // Safety: send all-notes-off to all instruments after scheduler is stopped
        instrumentManager?.allNotesOffAllTracks()
    }
    
    /// Seek to a new beat position - called on cycle loop
    func seek(toBeat positionBeats: Double) {
        scheduler.seek(toBeat: positionBeats)
    }
    
    // MARK: - Preview Playback
    
    /// Preview a single MIDI region (for auditioning in Piano Roll)
    func previewRegion(_ region: MIDIRegion, on trackId: UUID) {
        stop()
        
        var previewTrack = AudioTrack(name: "Preview", trackType: .midi)
        previewTrack.midiRegions = [region]
        
        scheduler.loadEvents(from: [previewTrack])
        isPlaying = true
        scheduler.play(fromBeat: 0)
    }
    
    /// Preview a single note (for Piano Roll editing)
    func previewNote(pitch: UInt8, velocity: UInt8 = 100, duration: TimeInterval = 0.3) {
        instrumentManager?.noteOn(pitch: pitch, velocity: velocity)
        
        // Schedule note off
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.instrumentManager?.noteOff(pitch: pitch)
        }
    }
}

// MARK: - MIDIPlaybackEngine + AudioEngine Integration

extension MIDIPlaybackEngine {
    
    /// Update tempo (call when project tempo changes)
    func setTempo(_ newTempo: Double) {
        self.tempo = newTempo
        
        // Update scheduler timing - it will create a new timing reference
        scheduler.updateTempo(newTempo)
    }
    
    /// Update sample rate (call when audio device changes)
    /// CRITICAL: Must update timing reference if playing to maintain timing accuracy
    func setSampleRate(_ newSampleRate: Double) {
        self.sampleRate = newSampleRate
        
        // If currently playing, update timing reference immediately
        if isPlaying {
            scheduler.updateSampleRate(newSampleRate)
        } else {
            // If not playing, just configure for next playback
            scheduler.configure(tempo: tempo, sampleRate: newSampleRate)
        }
    }
    
    /// Sync with AudioEngine transport state
    /// - Parameters:
    ///   - isPlaying: Whether transport is playing
    ///   - positionBeats: Current position in beats
    ///   - tracks: Tracks to load MIDI from
    ///   - tempo: Project tempo for beats→seconds conversion
    func syncWithTransport(isPlaying: Bool, positionBeats: Double, tracks: [AudioTrack], tempo: Double = 120.0) {
        if isPlaying {
            // Reload regions if not already playing
            if !self.isPlaying {
                loadRegions(from: tracks, tempo: tempo)
            }
            play(fromBeat: positionBeats)
        } else {
            stop()
        }
    }
    
    /// Called when project tracks change
    func reloadIfNeeded(tracks: [AudioTrack], tempo: Double = 120.0) {
        let wasPlaying = isPlaying
        let savedPositionBeats = currentPositionBeats
        
        if wasPlaying {
            stop()
        }
        
        loadRegions(from: tracks, tempo: tempo)
        
        if wasPlaying {
            play(fromBeat: savedPositionBeats)
        }
    }
    
    // MARK: - Thread-Safe MIDI Block Management
    
    /// Cache MIDI blocks for all MIDI tracks (call from MainActor when tracks change)
    func cacheMIDIBlocks(from tracks: [AudioTrack]) {
        var newBlocks: [UUID: AUScheduleMIDIEventBlock] = [:]
        
        for track in tracks where track.isMIDITrack {
            if let instrument = instrumentManager?.getInstrument(for: track.id),
               let midiBlock = instrument.getMIDIBlock() {
                newBlocks[track.id] = midiBlock
            }
        }
        
        // Atomically replace the cached blocks
        os_unfair_lock_lock(&midiBlockLock)
        midiBlocks = newBlocks
        os_unfair_lock_unlock(&midiBlockLock)
    }
    
    /// Sample-accurate MIDI dispatch with calculated sample time
    /// Called from the scheduler on the high-priority MIDI queue
    /// CRITICAL: This is the ONLY path for MIDI dispatch - no fallbacks
    nonisolated private func dispatchMIDIWithSampleTime(
        status: UInt8, data1: UInt8, data2: UInt8,
        trackId: UUID, sampleTime: AUEventSampleTime
    ) {
        // Get the cached MIDI block for this track
        os_unfair_lock_lock(&midiBlockLock)
        let midiBlock = midiBlocks[trackId]
        os_unfair_lock_unlock(&midiBlockLock)
        
        guard let block = midiBlock else {
            // REAL-TIME SAFETY: Simplified error handling - no allocations!
            // Set a flag to indicate missing block, actual error tracking happens off-thread
            // This is atomic and lock-free (just a bit set operation)
            // Note: Limited to 64 tracks - should be plenty for error detection
            let trackHash = UInt64(trackId.hashValue.magnitude) % 64
            let trackBit: UInt64 = 1 << trackHash
            
            // Check and set the flag atomically
            os_unfair_lock_lock(&missingBlockFlagsLock)
            let wasAlreadyFlagged = (missingBlockFlags & trackBit) != 0
            missingBlockFlags |= trackBit
            os_unfair_lock_unlock(&missingBlockFlagsLock)
            
            // Only schedule background error tracking if this is the first occurrence
            if !wasAlreadyFlagged {
                // Schedule error tracking OFF the audio thread
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.handleMissingMIDIBlock(trackId: trackId)
                }
            }
            return
        }
        
        // PDC: Get plugin latency compensation for this track
        // MIDI must be triggered EARLIER to compensate for plugin processing delay
        // This ensures MIDI output aligns with audio tracks
        let compensationSamples = PluginLatencyManager.shared.getCompensationDelay(for: trackId)
        
        // Apply negative compensation (trigger earlier)
        // If compensation is 1000 samples and sampleTime is 5000, we schedule at 4000
        let compensatedSampleTime = max(0, sampleTime - AUEventSampleTime(compensationSamples))
        
        // Clamp data bytes to valid MIDI range (0-127)
        let safeData1 = min(data1, 127)
        let safeData2 = min(data2, 127)
        
        // REAL-TIME SAFETY: Reuse pre-allocated buffer instead of allocating array
        // This eliminates malloc on every MIDI event (critical for real-time performance)
        midiDataBuffer[0] = status
        midiDataBuffer[1] = safeData1
        midiDataBuffer[2] = safeData2
        
        // Schedule with compensated sample time for phase-aligned timing
        // The AU will fire the event at exactly this sample offset
        block(compensatedSampleTime, 0, 3, &midiDataBuffer)
    }
    
    /// Handle missing MIDI block error (called on background thread)
    /// This moves all error tracking and logging off the audio thread
    @MainActor
    private func handleMissingMIDIBlock(trackId: UUID) {
        AppLogger.shared.warning("MIDI block missing for track \(trackId) - instrument not configured", category: .audio)
        
        AudioEngineErrorTracker.shared.recordError(
            severity: .error,
            component: "MIDIPlayback",
            message: "MIDI block missing - instrument not configured",
            context: ["trackId": trackId.uuidString]
        )
    }
}

