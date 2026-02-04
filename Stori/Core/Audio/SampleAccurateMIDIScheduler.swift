//
//  SampleAccurateMIDIScheduler.swift
//  Stori
//
//  Sample-accurate MIDI scheduling using calculated future sample times.
//  Events are scheduled with precise sample offsets for sub-sample accuracy.
//
//  ARCHITECTURE:
//  - Timer fires at 500Hz on a dedicated .userInteractive queue (pushes events ahead)
//  - Events are scheduled with calculated sample times (not immediate dispatch)
//  - Uses AUScheduleMIDIEventBlock with future sample times for true sample accuracy
//  - Thread-safe state access using os_unfair_lock
//
//  TIMING MODEL:
//  - Maintain a timing reference: (hostTime, sampleTime, beatPosition) captured at play start
//  - For each event, calculate: sampleTime = referenceSample + (eventBeat - referenceBeat) * samplesPerBeat
//  - Schedule events 50-100ms ahead to absorb timer jitter while AU handles precise timing
//

import Foundation
import AVFoundation
import os.lock

// MARK: - Audio Debug Configuration

/// Centralized debug flags for the audio subsystem.
/// In production builds, these are all disabled for optimal performance.
/// In debug builds, individual flags can be enabled for troubleshooting.
enum AudioDebugConfig {
    /// Master debug switch - must be true for any audio logging
    /// Set to false in production for zero logging overhead
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif
    
    /// Enable audio flow logging (graph mutations, connections)
    /// CAUTION: High CPU overhead when enabled
    static let logAudioFlow = false && isDebugBuild
    
    /// Enable mixer state logging (mute/solo/volume changes)
    static let logMixerState = false && isDebugBuild
    
    /// Enable plugin lifecycle logging (load/unload/bypass)
    static let logPluginLifecycle = false && isDebugBuild
    
    /// Enable MIDI scheduling logging
    static let logMIDIScheduling = false && isDebugBuild
    
    /// Enable transport logging (play/stop/seek)
    static let logTransport = false && isDebugBuild
    
    /// Enable automation logging
    static let logAutomation = false && isDebugBuild
    
    /// Enable sample rate/format logging
    static let logFormats = false && isDebugBuild
}

// MARK: - Audio Constants

/// Centralized audio constants for the DAW.
/// Adjust these values to tune performance vs. latency tradeoffs.
enum AudioConstants {
    
    // MARK: - Buffer Sizes
    
    /// Default buffer size in frames for plugin processing
    static let defaultBufferSize: AVAudioFrameCount = 512
    
    /// Buffer size for track-level metering taps (~21ms at 48kHz)
    /// Smaller = more responsive, larger = less CPU
    static let trackMeteringBufferSize: AVAudioFrameCount = 1024
    
    /// Buffer size for master/bus metering taps (~85ms at 48kHz)
    /// Larger buffer for LUFS time window calculations
    static let masterMeteringBufferSize: AVAudioFrameCount = 4096
    
    /// Buffer size for recording input taps
    static let recordingTapBufferSize: AVAudioFrameCount = 1024
    
    /// Maximum buffer capacity for recording (handles variable system buffer sizes)
    static let recordingMaxFrameCapacity: AVAudioFrameCount = 8192
    
    /// Buffer size for offline bounce rendering
    static let bounceChunkSize: Int = 4096
    
    // MARK: - Recording
    
    /// Recording buffer pool size (number of pre-allocated buffers)
    static let recordingPoolSize: Int = 16
    
    /// Sync interval (number of writes between fsync calls for crash protection)
    /// At 1024 frames/48kHz, 100 writes = ~2 seconds of audio
    static let recordingSyncInterval: Int = 100
    
    // MARK: - MIDI Scheduling
    
    /// MIDI scheduler lookahead in seconds (how far ahead to schedule events)
    static let midiLookaheadSeconds: Double = 0.050  // 50ms
    
    /// MIDI scheduler timer interval in milliseconds
    static let midiTimerIntervalMs: Int = 2  // 500Hz - lower frequency, sample-accurate timing
    
    // MARK: - Plugins
    
    /// Maximum tail time for plugins (caps reverb/delay tails)
    static let maxPluginTailTime: TimeInterval = 2.0
    
    /// Maximum plugin state size for restoration (prevents memory issues)
    static let maxPluginStateSize: Int = 10_000_000  // 10MB
    
    /// Plugin state restoration timeout
    static let pluginStateRestoreTimeout: TimeInterval = 5.0
    
    // MARK: - Automation
    
    /// Automation smoothing factor (exponential: out = out*α + target*(1-α)). 0 = instant, 1 = no change.
    /// ~50ms to 90% at 120Hz: α^6 ≈ 0.1 → α ≈ 0.68 (0.7 was ~175ms).
    static let automationSmoothingFactor: Float = 0.68
    
    /// Automation engine update frequency (Hz)
    static let automationUpdateFrequency: Double = 120.0
    
    // MARK: - Transport
    
    /// Position timer frequency (Hz) for UI updates
    static let positionTimerFrequency: Double = 60.0
    
    /// Minimum cooldown between cycle jumps (in buffer lengths)
    static let cycleJumpCooldownBuffers: Double = 2.0
    
    // MARK: - Metering
    
    /// Peak decay rate for track meters (per callback)
    /// 0.95 gives ~300ms release time at typical buffer rates
    static let trackPeakDecayRate: Float = 0.95
    
    /// Peak decay rate for master meter (per callback)
    static let masterPeakDecayRate: Float = 0.9
}

// MARK: - Scheduled MIDI Event (Beat-Based)

/// A MIDI event scheduled for playback at a specific beat position
struct ScheduledMIDIEventBeat: Comparable {
    /// Absolute position in beats
    let beat: Double
    
    /// MIDI status byte (note on/off, CC, etc.)
    let status: UInt8
    
    /// MIDI data byte 1 (pitch, controller number, etc.)
    let data1: UInt8
    
    /// MIDI data byte 2 (velocity, controller value, etc.)
    let data2: UInt8
    
    /// Track this event belongs to
    let trackId: UUID
    
    static func < (lhs: ScheduledMIDIEventBeat, rhs: ScheduledMIDIEventBeat) -> Bool {
        lhs.beat < rhs.beat
    }
    
    // MARK: - Factory Methods
    
    static func noteOn(at beat: Double, pitch: UInt8, velocity: UInt8, trackId: UUID, channel: UInt8 = 0) -> ScheduledMIDIEventBeat {
        ScheduledMIDIEventBeat(
            beat: beat,
            status: 0x90 | (channel & 0x0F),
            data1: pitch,
            data2: velocity,
            trackId: trackId
        )
    }
    
    static func noteOff(at beat: Double, pitch: UInt8, trackId: UUID, channel: UInt8 = 0) -> ScheduledMIDIEventBeat {
        ScheduledMIDIEventBeat(
            beat: beat,
            status: 0x80 | (channel & 0x0F),
            data1: pitch,
            data2: 0,
            trackId: trackId
        )
    }
    
    static func controlChange(at beat: Double, controller: UInt8, value: UInt8, trackId: UUID, channel: UInt8 = 0) -> ScheduledMIDIEventBeat {
        ScheduledMIDIEventBeat(
            beat: beat,
            status: 0xB0 | (channel & 0x0F),
            data1: controller,
            data2: value,
            trackId: trackId
        )
    }
    
    static func pitchBend(at beat: Double, value: Int16, trackId: UUID, channel: UInt8 = 0) -> ScheduledMIDIEventBeat {
        // Pitch bend uses 14-bit value: LSB in data1, MSB in data2
        // Convert signed -8192..8191 to unsigned 0..16383
        let midiValue = Int(value) + 8192
        let lsb = UInt8(midiValue & 0x7F)
        let msb = UInt8((midiValue >> 7) & 0x7F)
        return ScheduledMIDIEventBeat(
            beat: beat,
            status: 0xE0 | (channel & 0x0F),
            data1: lsb,
            data2: msb,
            trackId: trackId
        )
    }
}

// MARK: - Timing Reference

/// Captures a point-in-time reference for beat-to-sample conversion
/// Used to calculate precise sample times for MIDI events
struct MIDITimingReference {
    /// Host time (mach_absolute_time) when this reference was captured
    let hostTime: UInt64
    
    /// Wall clock time when this reference was created
    let createdAt: Date
    
    /// Beat position at the reference point
    let beatPosition: Double
    
    /// Tempo in BPM at the reference point
    let tempo: Double
    
    /// Sample rate of the audio engine
    let sampleRate: Double
    
    /// Pre-calculated samples per beat for efficiency
    var samplesPerBeat: Double {
        (60.0 / tempo) * sampleRate
    }
    
    /// Maximum age before timing reference is considered stale (seconds)
    /// After this time, accumulated drift could cause scheduling errors
    private static let maxReferenceAge: TimeInterval = 10.0
    
    /// Maximum reasonable elapsed samples before considering stale
    /// This catches system sleep/wake scenarios where mach_absolute_time jumps
    private static let maxReasonableElapsedSamples: Double = 10.0 * 48000.0 // 10 seconds at 48kHz
    
    /// Convert mach_absolute_time to nanoseconds
    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    
    /// Check if this timing reference is stale and should be regenerated
    /// Returns true if:
    /// - Reference is older than maxReferenceAge
    /// - System time appears to have jumped (sleep/wake)
    /// - Elapsed samples calculation seems unreasonable
    var isStale: Bool {
        // Check wall clock age
        let age = Date().timeIntervalSince(createdAt)
        if age > Self.maxReferenceAge {
            return true
        }
        
        // Check for unreasonable elapsed time (system sleep/wake detection)
        let currentHostTime = mach_absolute_time()
        let elapsedNanos = (currentHostTime - hostTime) * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
        let elapsedSamples = Double(elapsedNanos) / 1_000_000_000.0 * sampleRate
        
        // If elapsed samples is way higher than wall clock age would suggest,
        // system time jumped (sleep/wake)
        let expectedMaxSamples = age * sampleRate * 1.5  // 50% tolerance
        if elapsedSamples > expectedMaxSamples {
            return true
        }
        
        // Sanity check for extreme values
        if elapsedSamples > Self.maxReasonableElapsedSamples {
            return true
        }
        
        return false
    }
    
    /// Calculate the sample time for a given beat position
    /// - Parameter beat: The beat position to convert
    /// - Returns: The sample time (suitable for AUScheduleMIDIEventBlock)
    /// WARNING: Returns AUEventSampleTimeImmediate if reference is stale
    func sampleTime(forBeat beat: Double) -> AUEventSampleTime {
        // CRITICAL: If reference is stale, return immediate to avoid scheduling far in past
        if isStale {
            #if DEBUG
            // Only log in debug to avoid spam in production
            AppLogger.shared.warning("MIDI timing reference is stale - returning immediate", category: .audio)
            #endif
            return AUEventSampleTimeImmediate
        }
        
        let beatDelta = beat - beatPosition
        let sampleDelta = beatDelta * samplesPerBeat
        
        // Calculate elapsed samples from host time
        let currentHostTime = mach_absolute_time()
        let elapsedNanos = (currentHostTime - hostTime) * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
        let elapsedSamples = Double(elapsedNanos) / 1_000_000_000.0 * sampleRate
        
        // Target sample = (beat delta in samples) - (elapsed samples since reference)
        // Positive = future, negative = past
        let targetSampleOffset = sampleDelta - elapsedSamples
        
        // Return as sample offset from "now" (0 = immediate, positive = future)
        // AUEventSampleTime is Int64, positive values schedule into the future
        return AUEventSampleTime(max(0, targetSampleOffset))
    }
    
    /// Check if a beat position is in the past
    func isInPast(beat: Double) -> Bool {
        return sampleTime(forBeat: beat) <= 0
    }
    
    /// Create a new reference for the current moment
    static func now(beat: Double, tempo: Double, sampleRate: Double) -> MIDITimingReference {
        MIDITimingReference(
            hostTime: mach_absolute_time(),
            createdAt: Date(),
            beatPosition: beat,
            tempo: tempo,
            sampleRate: sampleRate
        )
    }
    
    /// Create a new reference from an AudioSchedulingContext
    /// - Parameters:
    ///   - beat: Current beat position
    ///   - context: The scheduling context for tempo and sample rate
    static func now(beat: Double, context: AudioSchedulingContext) -> MIDITimingReference {
        MIDITimingReference(
            hostTime: mach_absolute_time(),
            createdAt: Date(),
            beatPosition: beat,
            tempo: context.tempo,
            sampleRate: context.sampleRate
        )
    }
}

// MARK: - Sample-Accurate MIDI Scheduler

/// Sample-accurate MIDI scheduler using future sample time scheduling.
///
/// ARCHITECTURE:
/// Unlike the previous timer-based approach that dispatched events "immediately",
/// this scheduler calculates precise sample times for each event and schedules
/// them in advance using AUScheduleMIDIEventBlock's sample time parameter.
///
/// THREAD SAFETY:
/// - All mutable state is protected by `os_unfair_lock`
/// - Timer callback runs on dedicated high-priority queue
/// - MIDI blocks are called with calculated sample times
/// - Safe to call configuration methods from MainActor
///
/// TIMING:
/// - Timer fires at 500Hz to push events ahead (lower frequency than before)
/// - Events are scheduled with precise sample offsets (not immediate)
/// - Lookahead window of 50ms absorbs timer jitter
/// - Audio Unit handles sub-sample accurate timing
final class SampleAccurateMIDIScheduler: @unchecked Sendable {
    
    // MARK: - Thread Safety
    
    /// Lock for thread-safe access to scheduler state
    private var stateLock = os_unfair_lock_s()
    
    // MARK: - Scheduler State (Protected by stateLock)
    
    /// Pre-scheduled events sorted by beat
    private var scheduledEvents: [ScheduledMIDIEventBeat] = []
    
    /// Current index into scheduled events
    private var nextEventIndex: Int = 0
    
    /// Whether playback is active
    private var _isPlaying = false
    
    /// Cycle boundaries (in beats)
    private var cycleStartBeat: Double = 0
    private var cycleEndBeat: Double = Double.greatestFiniteMagnitude
    private var isCycleEnabled: Bool = false
    
    /// Active notes for tracking (for note-off on stop)
    private var activeNotes: [UInt8: UUID] = [:]  // pitch -> trackId
    
    /// Set of already-scheduled event indices (prevents double-scheduling)
    private var scheduledEventIndices: Set<Int> = []
    
    // MARK: - Timing Reference (Protected by stateLock)
    
    /// Current timing reference for beat-to-sample conversion
    private var timingReference: MIDITimingReference?
    
    /// Current tempo in BPM
    private var tempo: Double = 120.0
    
    /// Current sample rate
    private var sampleRate: Double = 48000.0
    
    // MARK: - Configuration
    
    /// Lookahead in seconds (schedule events this far ahead)
    /// Larger values absorb more jitter but increase latency
    private var lookaheadSeconds: Double { AudioConstants.midiLookaheadSeconds }
    
    /// Timer interval in milliseconds
    private var timerIntervalMs: Int { AudioConstants.midiTimerIntervalMs }
    
    /// Lookahead converted to beats at current tempo
    private var lookaheadBeats: Double {
        lookaheadSeconds * (tempo / 60.0)
    }
    
    // MARK: - Callbacks (Set Once, Thread-Safe to Read)
    
    /// Callback to get current beat position from transport
    /// Must be thread-safe and lock-free (reads atomic state)
    var currentBeatProvider: (() -> Double)?
    
    /// Callback to send MIDI to instruments with sample-accurate timing
    /// Called from high-priority queue - must be thread-safe
    /// Parameters: status, data1, data2, trackId, sampleTime
    /// CRITICAL: This is the ONLY MIDI dispatch path - no legacy fallbacks
    var sampleAccurateMIDIHandler: ((UInt8, UInt8, UInt8, UUID, AUEventSampleTime) -> Void)?
    
    // MARK: - Timer
    
    /// Dedicated high-priority queue for MIDI scheduling
    private let midiQueue = DispatchQueue(
        label: "com.stori.midi.scheduler",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    
    /// High-precision GCD timer
    private var schedulingTimer: DispatchSourceTimer?
    
    // MARK: - Public Properties
    
    /// Whether playback is active (thread-safe read)
    var isPlaying: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isPlaying
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Configuration (Call from MainActor)
    
    /// Configure timing parameters
    func configure(tempo: Double, sampleRate: Double) {
        os_unfair_lock_lock(&stateLock)
        self.tempo = tempo
        self.sampleRate = sampleRate
        os_unfair_lock_unlock(&stateLock)
    }
    
    /// Configure cycle region
    func setCycle(enabled: Bool, startBeat: Double, endBeat: Double) {
        os_unfair_lock_lock(&stateLock)
        self.isCycleEnabled = enabled
        self.cycleStartBeat = startBeat
        self.cycleEndBeat = endBeat
        os_unfair_lock_unlock(&stateLock)
    }
    
    // MARK: - Event Loading (Call from MainActor)
    
    /// Load MIDI events from tracks (all timing in beats)
    func loadEvents(from tracks: [AudioTrack]) {
        var newEvents: [ScheduledMIDIEventBeat] = []
        
        let hasSoloedTrack = tracks.contains { $0.mixerSettings.isSolo }
        
        for track in tracks where track.isMIDITrack {
            // Skip muted tracks
            if track.mixerSettings.isMuted { continue }
            
            // If any track is soloed, only play soloed tracks
            if hasSoloedTrack && !track.mixerSettings.isSolo { continue }
            
            for region in track.midiRegions where !region.isMuted {
                loadRegion(region, trackId: track.id, into: &newEvents)
            }
        }
        
        // Sort by beat
        newEvents.sort()
        
        // Atomically replace events
        os_unfair_lock_lock(&stateLock)
        scheduledEvents = newEvents
        scheduledEventIndices.removeAll()
        os_unfair_lock_unlock(&stateLock)
    }
    
    private func loadRegion(_ region: MIDIRegion, trackId: UUID, into events: inout [ScheduledMIDIEventBeat]) {
        let loopCount = region.isLooped ? region.loopCount : 1
        
        for loopIndex in 0..<loopCount {
            let loopOffsetBeats = Double(loopIndex) * region.durationBeats
            
            // Schedule note events
            for note in region.notes {
                let noteStartBeat = region.startBeat + note.startBeat + loopOffsetBeats
                let noteEndBeat = noteStartBeat + note.durationBeats
                
                events.append(.noteOn(
                    at: noteStartBeat,
                    pitch: note.pitch,
                    velocity: note.velocity,
                    trackId: trackId
                ))
                
                events.append(.noteOff(
                    at: noteEndBeat,
                    pitch: note.pitch,
                    trackId: trackId
                ))
            }
            
            // Schedule CC events
            for ccEvent in region.controllerEvents {
                let eventBeat = region.startBeat + ccEvent.beat + loopOffsetBeats
                
                events.append(.controlChange(
                    at: eventBeat,
                    controller: ccEvent.controller,
                    value: ccEvent.value,
                    trackId: trackId
                ))
            }
            
            // Schedule pitch bend events
            for pbEvent in region.pitchBendEvents {
                let eventBeat = region.startBeat + pbEvent.beat + loopOffsetBeats
                
                events.append(.pitchBend(
                    at: eventBeat,
                    value: pbEvent.value,
                    trackId: trackId
                ))
            }
        }
    }
    
    // MARK: - Playback Control (Call from MainActor)
    
    /// Start playback from a specific beat position
    func play(fromBeat startBeat: Double) {
        os_unfair_lock_lock(&stateLock)
        
        // Create timing reference for this playback session
        timingReference = MIDITimingReference.now(
            beat: startBeat,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        nextEventIndex = scheduledEvents.firstIndex { $0.beat >= startBeat } ?? scheduledEvents.count
        scheduledEventIndices.removeAll()
        _isPlaying = true
        os_unfair_lock_unlock(&stateLock)
        
        // Process events immediately to schedule ahead
        processScheduledEvents()
        
        // Start timer to keep pushing events ahead
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: midiQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(timerIntervalMs),
            repeating: .milliseconds(timerIntervalMs),
            leeway: .microseconds(500)  // Slightly relaxed - sample times handle precision
        )
        timer.setEventHandler { [weak self] in
            self?.processScheduledEvents()
        }
        timer.resume()
        schedulingTimer = timer
    }
    
    /// Stop playback and send note-offs for all active notes
    func stop() {
        // Cancel timer first
        schedulingTimer?.cancel()
        schedulingTimer = nil
        
        // Get active notes and clear state
        os_unfair_lock_lock(&stateLock)
        _isPlaying = false
        timingReference = nil
        let notesToRelease = activeNotes
        activeNotes.removeAll()
        scheduledEventIndices.removeAll()
        os_unfair_lock_unlock(&stateLock)
        
        // Send immediate note-offs (use AUEventSampleTimeImmediate for instant stop)
        guard let handler = sampleAccurateMIDIHandler else { return }
        for (pitch, trackId) in notesToRelease {
            handler(0x80, pitch, 0, trackId, AUEventSampleTimeImmediate)
        }
    }
    
    /// Seek to a new beat position
    func seek(toBeat beat: Double) {
        os_unfair_lock_lock(&stateLock)
        
        // Create new timing reference for the new position
        timingReference = MIDITimingReference.now(
            beat: beat,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        let notesToRelease = activeNotes
        activeNotes.removeAll()
        scheduledEventIndices.removeAll()
        nextEventIndex = scheduledEvents.firstIndex { $0.beat >= beat } ?? scheduledEvents.count
        
        os_unfair_lock_unlock(&stateLock)
        
        // Send immediate note-offs
        if let handler = sampleAccurateMIDIHandler {
            for (pitch, trackId) in notesToRelease {
                handler(0x80, pitch, 0, trackId, AUEventSampleTimeImmediate)
            }
        }
        
        // Process events at new position if playing
        if isPlaying {
            processScheduledEvents()
        }
    }
    
    /// Update timing reference when tempo changes
    func updateTempo(_ newTempo: Double) {
        guard let currentBeat = currentBeatProvider?() else { return }
        
        os_unfair_lock_lock(&stateLock)
        tempo = newTempo
        
        // Create new timing reference with updated tempo
        if _isPlaying {
            timingReference = MIDITimingReference.now(
                beat: currentBeat,
                tempo: newTempo,
                sampleRate: sampleRate
            )
        }
        os_unfair_lock_unlock(&stateLock)
    }
    
    /// Update timing reference when audio device sample rate changes
    /// Called when user switches audio interface (e.g., built-in → external interface)
    /// CRITICAL: Must regenerate timing reference with new sample rate to maintain timing accuracy
    func updateSampleRate(_ newSampleRate: Double) {
        guard let currentBeat = currentBeatProvider?() else { return }
        
        os_unfair_lock_lock(&stateLock)
        sampleRate = newSampleRate
        
        // Regenerate timing reference with new sample rate if currently playing
        if _isPlaying {
            timingReference = MIDITimingReference.now(
                beat: currentBeat,
                tempo: tempo,
                sampleRate: newSampleRate
            )
        }
        os_unfair_lock_unlock(&stateLock)
    }
    
    // MARK: - Event Processing (Called from Timer on midiQueue)
    
    /// Process scheduled events and schedule them with sample-accurate timing
    /// Called from timer - events are pushed ahead with calculated sample times
    private func processScheduledEvents() {
        // Get current beat from transport
        guard let currentBeat = currentBeatProvider?() else { return }
        
        // Collect events to dispatch with their sample times
        var eventsToDispatch: [(status: UInt8, data1: UInt8, data2: UInt8, trackId: UUID, sampleTime: AUEventSampleTime)] = []
        
        os_unfair_lock_lock(&stateLock)
        
        guard _isPlaying else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        
        // CRITICAL: Check if timing reference is stale and regenerate if needed
        if let timing = timingReference, timing.isStale {
            // Reference is stale - regenerate it to prevent drift
            timingReference = MIDITimingReference.now(
                beat: currentBeat,
                tempo: tempo,
                sampleRate: sampleRate
            )
            AppLogger.shared.info("MIDI: Regenerated stale timing reference at beat \(currentBeat)", category: .audio)
        }
        
        guard let timing = timingReference else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        
        // Calculate scheduling window: current beat to (current + lookahead)
        let targetBeat: Double
        if isCycleEnabled {
            targetBeat = min(currentBeat + lookaheadBeats, cycleEndBeat)
        } else {
            targetBeat = currentBeat + lookaheadBeats
        }
        
        while nextEventIndex < scheduledEvents.count {
            let eventIndex = nextEventIndex
            let event = scheduledEvents[eventIndex]
            
            // Skip events past cycle end when cycling
            if isCycleEnabled && event.beat >= cycleEndBeat {
                nextEventIndex += 1
                continue
            }
            
            // Stop if we've processed all events up to target
            if event.beat > targetBeat {
                break
            }
            
            // Skip if already scheduled (prevents double-fire on seek)
            if scheduledEventIndices.contains(eventIndex) {
                nextEventIndex += 1
                continue
            }
            
            // Calculate sample time for this event
            let sampleTime = timing.sampleTime(forBeat: event.beat)
            
            // Skip events that are too far in the past (more than 10ms)
            // These would have negative sample times
            if sampleTime < -Int64(sampleRate * 0.010) {
                nextEventIndex += 1
                continue
            }
            
            // Queue event for dispatch with calculated sample time
            // Clamp to immediate if slightly in the past
            let clampedSampleTime = max(0, sampleTime)
            eventsToDispatch.append((event.status, event.data1, event.data2, event.trackId, clampedSampleTime))
            
            // Mark as scheduled
            scheduledEventIndices.insert(eventIndex)
            
            // Track active notes
            let statusNibble = event.status & 0xF0
            if statusNibble == 0x90 && event.data2 > 0 {
                activeNotes[event.data1] = event.trackId
            } else if statusNibble == 0x80 || (statusNibble == 0x90 && event.data2 == 0) {
                activeNotes.removeValue(forKey: event.data1)
            }
            
            nextEventIndex += 1
        }
        
        os_unfair_lock_unlock(&stateLock)
        
        // Dispatch events outside lock with sample-accurate timing
        guard let handler = sampleAccurateMIDIHandler else {
            // No handler configured - this is a configuration error
            #if DEBUG
            if !eventsToDispatch.isEmpty {
                AppLogger.shared.warning("MIDI events dropped - no handler configured", category: .audio)
            }
            #endif
            return
        }
        
        for event in eventsToDispatch {
            handler(event.status, event.data1, event.data2, event.trackId, event.sampleTime)
        }
    }
}
