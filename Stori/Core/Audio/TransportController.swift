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
    nonisolated var atomicBeatPosition: Double {
        os_unfair_lock_lock(&beatPositionLock)
        defer { os_unfair_lock_unlock(&beatPositionLock) }
        
        guard _atomicIsPlaying else {
            return _atomicBeatPosition
        }
        
        // Calculate position from wall-clock delta (avoids timer jitter)
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
            print("🎵 PLAY FROM STOP: startBeat=0, wallTime=\(String(format: "%.6f", playbackStartWallTime)), tempo=\(project.tempo)")
            transportState = .playing
            onTransportStateChanged(.playing)
            
        case .paused:
            let resumeBeat = currentPosition.beats
            
            // CRITICAL FIX: Delay position updates to avoid visual playhead jump on resume.
            // Define delay in BEATS (tempo-aware), then convert to seconds.
            // This gives SwiftUI time to render the resume position before it starts advancing.
            let delayBeats: Double = 0.2  // ~1/8th note at 120 BPM
            let delaySeconds = (delayBeats * 60.0) / project.tempo
            
            // Adjust timing state forward by the delay so when timer fires, elapsed = 0
            playbackStartWallTime = CACurrentMediaTime() + delaySeconds
            playbackStartBeat = resumeBeat
            
            print("🎵 PLAY FROM PAUSE (RESUME):")
            print("    resumeBeat: \(String(format: "%.6f", resumeBeat))")
            print("    delayBeats: \(delayBeats) beats")
            print("    delaySeconds: \(String(format: "%.6f", delaySeconds))s @ \(project.tempo) BPM")
            print("    wallTime: \(String(format: "%.6f", playbackStartWallTime)) (adjusted +\(String(format: "%.3f", delaySeconds))s)")
            print("    tempo: \(project.tempo) BPM")
            print("    position: \(currentPosition.displayStringDefault)")
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
        // For resume, calculate beat-based delay; for play-from-stop, no delay needed
        let timerDelayBeats: Double
        let timerDelaySeconds: TimeInterval
        if transportState == .playing && playbackStartBeat > 0 {
            // Resuming - use beat-based delay to avoid visual jump
            timerDelayBeats = 0.2  // Matches delay above
            timerDelaySeconds = (timerDelayBeats * 60.0) / project.tempo
        } else {
            // Playing from stop - no delay needed
            timerDelayBeats = 0.0
            timerDelaySeconds = 0.0
        }
        setupPositionTimer(delaySeconds: timerDelaySeconds)
        
        startPlayback()
    }
    
    func pause() {
        guard transportState.isPlaying else { return }
        guard let project = getProject() else { return }
        
        // Capture exact stop position from wall clock (avoids using last timer tick, 0–16ms stale)
        let elapsedSeconds = CACurrentMediaTime() - playbackStartWallTime
        let beatsPerSecond = project.tempo / 60.0
        let exactStopBeat = playbackStartBeat + (elapsedSeconds * beatsPerSecond)
        print("⏸️  PAUSE:")
        print("    startBeat: \(String(format: "%.6f", playbackStartBeat))")
        print("    elapsedSeconds: \(String(format: "%.6f", elapsedSeconds))")
        print("    beatsPerSecond: \(String(format: "%.6f", beatsPerSecond))")
        print("    exactStopBeat: \(String(format: "%.6f", exactStopBeat))")
        print("    position: \(PlaybackPosition(beats: exactStopBeat, timeSignature: project.timeSignature, tempo: project.tempo).displayStringDefault)")
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
        print("⏹️  STOP: Resetting position to beat 0")
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
            print("    position: \(currentPosition.displayStringDefault)")
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
    
    func setupPositionTimer(delaySeconds: TimeInterval = 0) {
        // Cancel existing timer
        positionTimer?.cancel()
        positionTimer = nil
        
        // Capture current generation for this timer session
        positionUpdateGeneration = cycleGeneration
        
        // Create high-priority timer that's immune to main thread blocking.
        // CRITICAL: For resume, start timer after a beat-based delay (converted to seconds).
        // After resume, the main thread is busy (audio start, MIDI scheduling, state updates)
        // causing SwiftUI to batch/drop render frames. Logs show it takes ~100ms for the first
        // render to happen. If we start updating position before that first render, the playhead
        // jumps ahead visually. By waiting (beat-aware delay), we ensure at least one clean render
        // of the resume position before position starts advancing.
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: positionQueue)
        let delayMs = Int(delaySeconds * 1000)
        timer.schedule(
            deadline: delayMs > 0 ? .now() + .milliseconds(delayMs) : .now(),
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
            return
        }
        guard let project = getProject() else { return }
        
        // Check if a cycle jump occurred - if so, skip this update
        // The jump already set the correct position
        if positionUpdateGeneration != cycleGeneration {
            positionUpdateGeneration = cycleGeneration
            return
        }
        
        // Calculate elapsed time since playback started using captured wall time
        // (captured on background queue when timer fired, not when this runs on MainActor)
        let elapsedSeconds = capturedWallTime - playbackStartWallTime
        
        // Convert elapsed seconds to elapsed beats
        let beatsPerSecond = project.tempo / 60.0
        let elapsedBeats = elapsedSeconds * beatsPerSecond
        
        // Current position = start position + elapsed beats
        let currentBeat = playbackStartBeat + elapsedBeats
        
        // First update after resume? Log it with detailed timing
        if lastStartBeat != playbackStartBeat {
            print("⏱️  FIRST POSITION UPDATE AFTER STATE CHANGE:")
            print("    playbackStartBeat: \(String(format: "%.6f", playbackStartBeat))")
            print("    capturedWallTime: \(String(format: "%.6f", capturedWallTime))")
            print("    playbackStartWallTime: \(String(format: "%.6f", playbackStartWallTime))")
            print("    elapsedSeconds: \(String(format: "%.6f", elapsedSeconds))")
            print("    beatsPerSecond: \(String(format: "%.6f", beatsPerSecond))")
            print("    elapsedBeats: \(String(format: "%.6f", elapsedBeats))")
            print("    currentBeat: \(String(format: "%.6f", currentBeat))")
            let position = PlaybackPosition(beats: currentBeat, timeSignature: project.timeSignature, tempo: project.tempo)
            print("    displayPosition: \(position.displayStringDefault)")
            lastStartBeat = playbackStartBeat
        }
        
        currentPosition = PlaybackPosition(beats: currentBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        
        // Update atomic state for MIDI scheduler
        updateAtomicBeatPosition(currentBeat, isPlaying: true)
        
        onPositionChanged(currentPosition)
        
        // Check for cycle loop
        checkCycleLoop()
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
        
        // Tighter epsilon for accurate detection
        let beatEpsilon = 0.005
        
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
        
        // Stop current playback
        onStopPlayback()
        
        // Update timing state
        playbackStartBeat = targetBeat
        playbackStartWallTime = CACurrentMediaTime()
        
        // Update position immediately
        currentPosition = PlaybackPosition(beats: targetBeat, timeSignature: project.timeSignature, tempo: project.tempo)
        onPositionChanged(currentPosition)
        
        // Update atomic timing state for MIDI scheduler (wall-clock based)
        updateAtomicTimingState(
            startBeat: targetBeat,
            wallTime: playbackStartWallTime,
            tempo: project.tempo,
            isPlaying: true
        )
        
        // Notify for cycle jump handling (metronome, MIDI, etc.)
        onCycleJump(targetBeat)
        
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
