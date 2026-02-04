//
//  TransportController.swift
//  Stori
//
//  Manages transport state, playback scheduling, position tracking, and cycle/loop behavior.
//  Extracted from AudioEngine for better separation of concerns.
//
//  ARCHITECTURE: Beats-First
//  - All positions are stored and tracked in beats (musical time)
//  - Seconds are only used when interfacing with AVAudioEngine callbacks
//  - Conversion happens at the boundary via beatsToSeconds/secondsToBeats
//
//  THREAD SAFETY:
//  - UI state (@Observable) is MainActor-isolated
//  - Beat position for MIDI scheduler is accessible from any thread via atomic storage
//  - Position timer uses DispatchSourceTimer on high-priority queue (immune to main thread blocking)
//  - Cycle jumps use generation counter to avoid races
//

import Foundation
import AVFoundation
import QuartzCore
import os.lock

/// Transport controller manages playback state, position tracking, and cycle behavior.
/// It coordinates with AudioEngine via callbacks for actual audio operations.
/// All positions are tracked in BEATS - seconds are only used at AVAudioEngine boundary.
@Observable
@MainActor
class TransportController {
    
    // MARK: - Observable Transport State
    var transportState: TransportState = .stopped
    var currentPosition: PlaybackPosition = PlaybackPosition()
    var isCycleEnabled: Bool = false
    var cycleStartBeat: Double = 0.0
    var cycleEndBeat: Double = 4.0
    
    // MARK: - Thread-Safe Beat Position (for MIDI Scheduler)
    // Protected by os_unfair_lock, accessible from any thread
    
    /// Lock for thread-safe access to atomic beat position and timing state
    @ObservationIgnored
    private nonisolated(unsafe) var beatPositionLock = os_unfair_lock_s()
    
    /// Atomic storage for current beat position (readable from any thread)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicBeatPosition: Double = 0
    
    /// Atomic storage for whether transport is playing (readable from any thread)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicIsPlaying: Bool = false
    
    /// Atomic storage for playback start beat (for wall-clock calculation)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicPlaybackStartBeat: Double = 0
    
    /// Atomic storage for playback start wall time (for wall-clock calculation)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicPlaybackStartWallTime: TimeInterval = 0
    
    /// Atomic storage for tempo (for beat calculation from any thread)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicTempo: Double = 120.0
    
    /// Thread-safe read of current beat position (for MIDI scheduler)
    /// Calculates position from wall-clock delta for maximum accuracy
    /// Thread-safe read of current beat position (for MIDI scheduler, metronome, recording)
    /// CRITICAL: This is accessed from audio threads - must be real-time safe!
    /// FORMULA: currentBeat = startBeat + (elapsedSeconds * (tempo / 60.0))
    /// NOTE: This calculation MUST match calculateCurrentBeat() to maintain consistency
    nonisolated var atomicBeatPosition: Double {
        os_unfair_lock_lock(&beatPositionLock)
        defer { os_unfair_lock_unlock(&beatPositionLock) }
        
        guard _atomicIsPlaying else {
            return _atomicBeatPosition
        }
        
        // Calculate position from wall-clock delta (avoids timer jitter)
        // FORMULA: Same as calculateCurrentBeat() - DO NOT DIVERGE!
        let elapsedSeconds = CACurrentMediaTime() - _atomicPlaybackStartWallTime
        let beatsPerSecond = _atomicTempo / 60.0
        return _atomicPlaybackStartBeat + (elapsedSeconds * beatsPerSecond)
    }
    
    /// Thread-safe read of playing state (for MIDI scheduler)
    nonisolated var atomicIsPlaying: Bool {
        os_unfair_lock_lock(&beatPositionLock)
        defer { os_unfair_lock_unlock(&beatPositionLock) }
        return _atomicIsPlaying
    }
    
    /// Update atomic timing state (called when playback starts/seeks)
    private func updateAtomicTimingState(startBeat: Double, wallTime: TimeInterval, tempo: Double, isPlaying: Bool) {
        os_unfair_lock_lock(&beatPositionLock)
        _atomicPlaybackStartBeat = startBeat
        _atomicPlaybackStartWallTime = wallTime
        _atomicTempo = tempo
        _atomicIsPlaying = isPlaying
        _atomicBeatPosition = startBeat
        os_unfair_lock_unlock(&beatPositionLock)
    }
    
    /// Update atomic beat position (for stopped/paused states)
    private func updateAtomicBeatPosition(_ beat: Double, isPlaying: Bool) {
        os_unfair_lock_lock(&beatPositionLock)
        _atomicBeatPosition = beat
        _atomicIsPlaying = isPlaying
        os_unfair_lock_unlock(&beatPositionLock)
    }
    
    // MARK: - Timing State (Beats-First)
    
    /// The beat position when playback started/resumed
    @ObservationIgnored
    private var playbackStartBeat: Double = 0
    
    /// Wall-clock time when playback started (for calculating elapsed time)
    @ObservationIgnored
    private var playbackStartWallTime: TimeInterval = 0
    
    // MARK: - Position Timer (High-Priority DispatchSourceTimer)
    
    /// High-priority queue for position updates (immune to main thread blocking)
    @ObservationIgnored
    private let positionQueue = DispatchQueue(
        label: "com.stori.transport.position",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    
    /// High-precision timer for position updates (60 FPS for UI)
    @ObservationIgnored
    private var positionTimer: DispatchSourceTimer?
    
    // MARK: - Cycle Loop State (Generation Counter Pattern)
    
    /// Generation counter for cycle jumps - incremented on each jump
    /// Position updates check this to avoid publishing stale positions
    @ObservationIgnored
    private var cycleGeneration: Int = 0
    
    /// Generation at start of current position update cycle
    @ObservationIgnored
    private var positionUpdateGeneration: Int = 0
    
    /// Cooldown tracking for cycle jumps
    @ObservationIgnored
    private var lastCycleJumpTime: TimeInterval = 0
    
    /// Debug tracking: last playback start beat for detecting resume events
    @ObservationIgnored
    private var lastStartBeat: Double? = nil
    
    // MARK: - Dependencies (injected via closures for loose coupling)
    
    /// Returns current project
    @ObservationIgnored
    private var getProject: () -> AudioProject?
    
    /// Returns whether plugin installation is in progress
    @ObservationIgnored
    private var isInstallingPlugin: () -> Bool
    
    /// Returns whether audio graph is stable
    @ObservationIgnored
    private var isGraphStable: () -> Bool
    
    /// Returns current hardware sample rate
    @ObservationIgnored
    private var getSampleRate: () -> Double
    
    /// Callback to start audio playback on all tracks (receives beat position)
    @ObservationIgnored
    private var onStartPlayback: (_ fromBeat: Double) -> Void
    
    /// Callback to stop audio playback on all tracks
    @ObservationIgnored
    private var onStopPlayback: () -> Void
    
    /// Callback for transport state changes
    @ObservationIgnored
    private var onTransportStateChanged: (TransportState) -> Void
    
    /// Callback for position changes (used for automation, etc.)
    @ObservationIgnored
    private var onPositionChanged: (PlaybackPosition) -> Void
    
    /// Callback when a cycle jump occurs (receives beat position)
    @ObservationIgnored
    private var onCycleJump: (_ toBeat: Double) -> Void
    
    // MARK: - Initialization
    
    init(
        getProject: @escaping () -> AudioProject?,
        isInstallingPlugin: @escaping () -> Bool,
        isGraphStable: @escaping () -> Bool,
        getSampleRate: @escaping () -> Double = { 48000 },
        onStartPlayback: @escaping (_ fromBeat: Double) -> Void,
        onStopPlayback: @escaping () -> Void,
        onTransportStateChanged: @escaping (TransportState) -> Void,
        onPositionChanged: @escaping (PlaybackPosition) -> Void,
        onCycleJump: @escaping (_ toBeat: Double) -> Void
    ) {
        self.getProject = getProject
        self.isInstallingPlugin = isInstallingPlugin
        self.isGraphStable = isGraphStable
        self.getSampleRate = getSampleRate
        self.onStartPlayback = onStartPlayback
        self.onStopPlayback = onStopPlayback
        self.onTransportStateChanged = onTransportStateChanged
        self.onPositionChanged = onPositionChanged
        self.onCycleJump = onCycleJump
    }
    
    nonisolated deinit {
        // Ensure position timer is stopped to prevent memory leaks
        // Cancel the timer directly since deinit is nonisolated
        positionTimer?.cancel()
    }
    
    // MARK: - Transport Controls
    
    func play() {
        // Block during plugin installation
        if isInstallingPlugin() {
            return
        }
        
        // Block while graph is unstable
        if !isGraphStable() {
            return
        }
        
        guard let project = getProject() else {
            return
        }
        
        switch transportState {
        case .stopped:
            playbackStartWallTime = CACurrentMediaTime()
            playbackStartBeat = 0
            transportState = .playing
            onTransportStateChanged(.playing)
            
        case .paused:
            let resumeBeat = currentPosition.beats
            playbackStartWallTime = CACurrentMediaTime()
            playbackStartBeat = resumeBeat
            print("🟢 RESUME: from beat \(resumeBeat), wallTime=\(playbackStartWallTime)")
            transportState = .playing
            onTransportStateChanged(.playing)
            
            // Ensure UI has the resume position (even though it hasn't changed since pause)
            onPositionChanged(currentPosition)
            
        case .playing, .recording:
            return // Already playing
        }
        
        // Update atomic timing state for MIDI scheduler (wall-clock based calculation)
        updateAtomicTimingState(
            startBeat: playbackStartBeat,
            wallTime: playbackStartWallTime,
            tempo: project.tempo,
            isPlaying: true
        )
        
        // Restart position timer
        setupPositionTimer()
        
        startPlayback()
    }
    
    func pause() {
        guard transportState.isPlaying else { return }
        guard let project = getProject() else { return }
        
        // Capture exact stop position from wall clock (avoids using last timer tick, 0–16ms stale)
        let elapsedSeconds = CACurrentMediaTime() - playbackStartWallTime
        let beatsPerSecond = project.tempo / 60.0
        let exactStopBeat = playbackStartBeat + (elapsedSeconds * beatsPerSecond)
        print("🔴 PAUSE: startBeat=\(playbackStartBeat), elapsed=\(elapsedSeconds)s, stopBeat=\(exactStopBeat)")
        currentPosition = PlaybackPosition(beats: exactStopBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        onPositionChanged(currentPosition)
        
        transportState = .paused
        onTransportStateChanged(.paused)
        stopPlayback()
        
        // Update atomic state with exact stop position
        updateAtomicBeatPosition(exactStopBeat, isPlaying: false)
        
        // Stop position timer to save CPU
        stopPositionTimer()
    }
    
    func stop() {
        transportState = .stopped
        onTransportStateChanged(.stopped)
        stopPlayback()
        
        // Stop position timer
        stopPositionTimer()
        
        // Reset position to beat 0
        playbackStartBeat = 0
        if let project = getProject() {
            currentPosition = PlaybackPosition(beats: 0, timeSignature: project.timeSignature, tempo: project.tempo)
            onPositionChanged(currentPosition)
        }
        
        // Update atomic state
        updateAtomicBeatPosition(0, isPlaying: false)
    }
    
    /// Start recording mode
    func startRecordingMode() {
        transportState = .recording
        onTransportStateChanged(.recording)
    }
    
    /// Stop recording mode (returns to stopped)
    func stopRecordingMode() {
        transportState = .stopped
        onTransportStateChanged(.stopped)
    }
    
    // MARK: - Position Control (Beats-First)
    
    /// Seek to a specific beat position (primary method)
    func seekToBeat(_ beat: Double) {
        guard let project = getProject() else { return }
        
        let wasPlaying = transportState.isPlaying
        
        if wasPlaying {
            stopPlayback()
        }
        
        let targetBeat = max(0, beat)
        playbackStartBeat = targetBeat
        playbackStartWallTime = CACurrentMediaTime()
        currentPosition = PlaybackPosition(beats: targetBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        onPositionChanged(currentPosition)
        
        // Update atomic timing state
        if wasPlaying {
            updateAtomicTimingState(
                startBeat: targetBeat,
                wallTime: playbackStartWallTime,
                tempo: project.tempo,
                isPlaying: true
            )
            startPlayback()
        } else {
            updateAtomicBeatPosition(targetBeat, isPlaying: false)
        }
    }
    
    /// Convenience: Seek using seconds (converts to beats internally)
    func seekToSeconds(_ seconds: TimeInterval) {
        guard let project = getProject() else { return }
        let beats = seconds * (project.tempo / 60.0)
        seekToBeat(beats)
    }
    
    // MARK: - Cycle Controls
    
    func toggleCycle() {
        isCycleEnabled.toggle()
    }
    
    func setCycleRegion(startBeat: Double, endBeat: Double) {
        cycleStartBeat = round(max(0, startBeat) * 1000) / 1000
        cycleEndBeat = round(max(cycleStartBeat + 0.25, endBeat) * 1000) / 1000
    }
    
    // MARK: - Tempo Sync
    
    /// Resync timing references when tempo changes during playback.
    func syncTempoChange() {
        guard transportState.isPlaying else { return }
        guard let project = getProject() else { return }
        
        // Capture current beat position before tempo change takes effect
        let currentBeat = currentPosition.beats
        
        // Reset timing references
        playbackStartBeat = currentBeat
        playbackStartWallTime = CACurrentMediaTime()
        
        // Update atomic timing state with new tempo
        updateAtomicTimingState(
            startBeat: currentBeat,
            wallTime: playbackStartWallTime,
            tempo: project.tempo,
            isPlaying: true
        )
    }
    
    // MARK: - Position Timer (High-Priority DispatchSourceTimer)
    
    func setupPositionTimer() {
        // Cancel existing timer
        positionTimer?.cancel()
        positionTimer = nil
        
        // Capture current generation for this timer session
        positionUpdateGeneration = cycleGeneration
        
        // Create high-priority timer that's immune to main thread blocking.
        // Fire immediately first, then every 16ms. We capture wall time on the background queue
        // before dispatching to MainActor, so the elapsed time calculation is accurate even if
        // the main thread is busy.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: positionQueue)
        timer.schedule(
            deadline: .now(),  // Fire immediately for smooth resume
            repeating: .milliseconds(16),  // ~60 FPS
            leeway: .microseconds(500)
        )
        timer.setEventHandler { [weak self] in
            // CRITICAL FIX: Capture wall time NOW (on background queue) before dispatching to MainActor.
            // If we calculate elapsed time on MainActor, and MainActor is blocked by resume work
            // (starting audio engine, MIDI, etc.), the Task might not run for 100+ ms, causing
            // elapsedSeconds to be stale and the playhead to jump forward.
            let capturedWallTime = CACurrentMediaTime()
            
            // Dispatch to MainActor for UI updates with captured time
            Task { @MainActor in
                self?.updatePosition(capturedWallTime: capturedWallTime)
            }
        }
        timer.resume()
        positionTimer = timer
    }
    
    func stopPositionTimer() {
        positionTimer?.cancel()
        positionTimer = nil
    }
    
    private func updatePosition(capturedWallTime: TimeInterval) {
        guard transportState.isPlaying else {
            print("⚠️ updatePosition() called but not playing (state: \(transportState))")
            return
        }
        guard let project = getProject() else { return }
        
        // Check if a cycle jump occurred - if so, skip this update
        // The jump already set the correct position
        if positionUpdateGeneration != cycleGeneration {
            positionUpdateGeneration = cycleGeneration
            return
        }
        
        // CRITICAL FIX: Use atomic position calculation (single source of truth)
        // This ensures timer-based position matches MIDI scheduler's position exactly
        // Previous approach duplicated calculation logic → potential for divergence
        let currentBeat = calculateCurrentBeat(
            startBeat: playbackStartBeat,
            startWallTime: playbackStartWallTime,
            currentWallTime: capturedWallTime,
            tempo: project.tempo
        )
        
        // First update after resume? Log it
        if lastStartBeat != playbackStartBeat {
            let elapsedSeconds = capturedWallTime - playbackStartWallTime
            let elapsedBeats = currentBeat - playbackStartBeat
            print("⏱️  FIRST UPDATE: startBeat=\(playbackStartBeat), elapsed=\(elapsedSeconds)s (\(elapsedBeats) beats), currentBeat=\(currentBeat)")
            lastStartBeat = playbackStartBeat
        }

        currentPosition = PlaybackPosition(beats: currentBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        
        // Update atomic state for MIDI scheduler
        updateAtomicBeatPosition(currentBeat, isPlaying: true)
        
        onPositionChanged(currentPosition)
        
        // Check for cycle loop
        checkCycleLoop()
    }
    
    /// Calculate current beat position from wall-clock time (shared calculation logic)
    /// This is the SINGLE SOURCE OF TRUTH for beat position calculation
    private func calculateCurrentBeat(startBeat: Double, startWallTime: TimeInterval, currentWallTime: TimeInterval, tempo: Double) -> Double {
        let elapsedSeconds = currentWallTime - startWallTime
        let beatsPerSecond = tempo / 60.0
        let elapsedBeats = elapsedSeconds * beatsPerSecond
        return startBeat + elapsedBeats
    }
    
    private func checkCycleLoop() {
        guard isCycleEnabled else { return }
        guard transportState.isPlaying else { return }
        
        let currentSystemTime = CACurrentMediaTime()
        
        // Calculate cooldown based on tempo and actual sample rate
        let cooldown = calculateCycleCooldown()
        
        // Ensure cooldown period has elapsed since last cycle jump (prevents rapid loops)
        guard currentSystemTime - lastCycleJumpTime >= cooldown else {
            return
        }
        
        let currentBeat = currentPosition.beats
        
        // CRITICAL FIX: Tighter epsilon for sub-millisecond accuracy
        // At 120 BPM, 0.001 beats ≈ 0.5ms (imperceptible to human ear)
        // Previous 0.005 beats ≈ 2.5ms could cause audible drift
        let beatEpsilon = 0.001
        
        if currentBeat >= (cycleEndBeat - beatEpsilon) {
            lastCycleJumpTime = currentSystemTime
            transportSafeJump(toBeat: cycleStartBeat)
        }
    }
    
    /// Calculate cycle cooldown based on tempo and hardware sample rate
    private func calculateCycleCooldown() -> TimeInterval {
        guard let project = getProject() else {
            return 0.05 // Fallback: 50ms
        }
        
        let sampleRate = getSampleRate()
        let bufferSize: Double = 1024
        let minCooldown = (bufferSize * 2) / sampleRate
        
        let secondsPerBeat = 60.0 / project.tempo
        let maxCooldown = secondsPerBeat / 8.0
        
        return max(minCooldown, min(maxCooldown, 0.1))
    }
    
    // MARK: - Transport Safe Jump (Generation Counter Pattern)
    
    /// Jump to a beat position while transport is running (for cycle loops)
    /// Uses generation counter to avoid race conditions with position timer.
    func transportSafeJump(toBeat targetBeat: Double) {
        guard transportState.isPlaying else { return }
        guard let project = getProject() else { return }
        
        // Increment generation to invalidate any in-flight position updates
        cycleGeneration += 1
        
        // CRITICAL FIX: Update atomic timing state FIRST (before stopping/restarting)
        // This ensures MIDI scheduler and metronome have correct timing reference
        // when they receive the cycle jump notification
        let jumpWallTime = CACurrentMediaTime()
        updateAtomicTimingState(
            startBeat: targetBeat,
            wallTime: jumpWallTime,
            tempo: project.tempo,
            isPlaying: true
        )
        
        // Update timing state
        playbackStartBeat = targetBeat
        playbackStartWallTime = jumpWallTime
        
        // Update position immediately
        currentPosition = PlaybackPosition(beats: targetBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        onPositionChanged(currentPosition)
        
        // CRITICAL FIX: Notify for cycle jump handling BEFORE stopping/restarting
        // This allows MIDI scheduler to send note-offs and prepare for seamless jump
        // Metronome can also pre-schedule clicks at the target position
        onCycleJump(targetBeat)
        
        // Stop current playback (will stop scheduled audio)
        onStopPlayback()
        
        // Restart playback from the target beat
        onStartPlayback(targetBeat)
        
        // Update the position timer's generation to match
        positionUpdateGeneration = cycleGeneration
    }
    
    // MARK: - Private Helpers
    
    private func startPlayback() {
        let startBeat = currentPosition.beats
        onStartPlayback(startBeat)
    }
    
    private func stopPlayback() {
        onStopPlayback()
    }
    
    // MARK: - State Accessors
    
    var isPlaying: Bool {
        transportState.isPlaying
    }
    
    var isStopped: Bool {
        transportState == .stopped
    }
    
    var isPaused: Bool {
        transportState == .paused
    }
    
    var isRecording: Bool {
        transportState == .recording
    }
    
    /// Current playhead position in beats (primary)
    var positionBeats: Double {
        currentPosition.beats
    }
    
    /// Current playhead position in seconds (for AVAudioEngine boundary only)
    func positionSeconds(tempo: Double) -> TimeInterval {
        currentPosition.beats * (60.0 / tempo)
    }
}
