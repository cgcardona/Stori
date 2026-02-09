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
//  NOTE: @preconcurrency import must be the first import of that module in this file (Swift compiler limitation).
@preconcurrency import AVFoundation
import Foundation
import QuartzCore
import os.lock

/// Helper class for non-isolated timer cleanup (Swift 6.1 workaround for isolated deinit)
/// The deinit of this helper implicitly runs on MainActor when parent is deallocated
/// This pattern is required until Swift 6.2 when isolated deinit becomes available
private final class PositionTimerHolder {
    var timer: DispatchSourceTimer?
    
    deinit {
        // This deinit is implicitly nonisolated and can safely cancel the timer
        // When TransportController (MainActor) is deallocated, this helper is too
        timer?.cancel()
    }
}

/// Nonisolated relay for the position timer's event handler.
///
/// DispatchSourceTimer event handlers run on a background serial queue.
/// In Swift 6, closures formed inside a `@MainActor` method inherit that
/// isolation, causing a runtime `_dispatch_assert_queue_fail` when they
/// fire on a non-main queue.
///
/// By moving the event handler installation into this nonisolated class's
/// method, the closure is formed in a nonisolated context and won't
/// inherit `@MainActor`.
private final class PositionTimerRelay: @unchecked Sendable {
    var onTick: (@MainActor (TimeInterval) -> Void)?
    
    /// Install the event handler on the timer. Must be called from this
    /// nonisolated context so the closure does not inherit @MainActor.
    func installHandler(on timer: DispatchSourceTimer) {
        timer.setEventHandler {
            let capturedWallTime = CACurrentMediaTime()
            let handler = self.onTick
            Task { @MainActor in
                handler?(capturedWallTime)
            }
        }
    }
}

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
    /// Wrapped in helper class for safe non-isolated cleanup (Swift 6.1 workaround)
    @ObservationIgnored
    private let timerHolder = PositionTimerHolder()
    
    /// Convenience accessor for position timer
    private var positionTimer: DispatchSourceTimer? {
        get { timerHolder.timer }
        set { timerHolder.timer = newValue }
    }
    
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
        
        // Setup save coordination notifications (Issue #63)
        setupSaveCoordinationObservers()
    }
    
    // MARK: - Save Coordination (Issue #63)
    
    /// Temporary pause state for save operation
    @ObservationIgnored
    private var savedStateBeforeSavePause: TransportState = .stopped
    
    /// Setup notification observers for save coordination
    /// CRITICAL (Issue #63): These ensure consistent project state during save
    private func setupSaveCoordinationObservers() {
        // Query transport state
        NotificationCenter.default.addObserver(
            forName: .queryTransportState,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            // Extract coordinator and call synchronously (coordinator is thread-safe)
            if let coordinator = notification.userInfo?["coordinator"] as? TransportQueryCoordinator {
                let isPlaying = MainActor.assumeIsolated { self.isPlaying }
                coordinator.resumeOnce(returning: isPlaying)
            }
        }
        
        // Pause transport for save
        NotificationCenter.default.addObserver(
            forName: .pauseTransportForSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Already on main queue, execute synchronously
            MainActor.assumeIsolated {
                // Save current state and pause
                self.savedStateBeforeSavePause = self.transportState
                if self.isPlaying {
                    self.pause()
                }
                
                // Confirm pause to ProjectManager
                NotificationCenter.default.post(name: .transportPausedForSave, object: nil)
            }
        }
        
        // Resume transport after save
        NotificationCenter.default.addObserver(
            forName: .resumeTransportAfterSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Already on main queue, execute synchronously
            MainActor.assumeIsolated {
                // Only resume if we were playing before save
                if self.savedStateBeforeSavePause == .playing {
                    self.play()
                }
            }
        }
    }
    
    // MARK: - Cleanup
    // NOTE: Explicit deinit removed - cleanup now handled by PositionTimerHolder
    // This is a Swift 6.1 workaround until isolated deinit becomes available in Swift 6.2
    // See: https://forums.swift.org/t/isolated-deinit-not-in-swift-6-1/78055
    
    // MARK: - Transport Controls
    
    func play() {
        if isInstallingPlugin() { return }
        if !isGraphStable() { return }
        guard let project = getProject() else { return }
        
        switch transportState {
        case .stopped:
            playbackStartWallTime = CACurrentMediaTime()
            playbackStartBeat = 0
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
            
            // DEBUG: Resume timing logs disabled for production
            // print("🎵 PLAY FROM PAUSE (RESUME):")
            // print("    resumeBeat: \(String(format: "%.6f", resumeBeat))")
            // print("    delayBeats: \(delayBeats) beats")
            // print("    delaySeconds: \(String(format: "%.6f", delaySeconds))s @ \(project.tempo) BPM")
            // print("    wallTime: \(String(format: "%.6f", playbackStartWallTime)) (adjusted +\(String(format: "%.3f", delaySeconds))s)")
            // print("    tempo: \(project.tempo) BPM")
            // print("    position: \(currentPosition.displayStringDefault)")
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
            // print("    position: \(currentPosition.displayStringDefault)")  // DEBUG: Disabled for production
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
        stopPlayback()
        
        // Stop position timer
        stopPositionTimer()
        
        // Reset position to beat 0 (Logic Pro behavior: stop = return to beginning)
        playbackStartBeat = 0
        if let project = getProject() {
            currentPosition = PlaybackPosition(beats: 0, timeSignature: project.timeSignature, tempo: project.tempo)
            onPositionChanged(currentPosition)
        }
        
        // Update atomic state
        updateAtomicBeatPosition(0, isPlaying: false)
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
        // Use a nonisolated relay to form the event handler closure outside
        // of @MainActor context. See PositionTimerRelay doc comment for details.
        let relay = PositionTimerRelay()
        relay.onTick = { [weak self] capturedWallTime in
            self?.updatePosition(capturedWallTime: capturedWallTime)
        }
        relay.installHandler(on: timer)
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
        
        // CRITICAL FIX: Use atomic position calculation (single source of truth)
        // This ensures timer-based position matches MIDI scheduler's position exactly
        // Previous approach duplicated calculation logic → potential for divergence
        let currentBeat = calculateCurrentBeat(
            startBeat: playbackStartBeat,
            startWallTime: playbackStartWallTime,
            currentWallTime: capturedWallTime,
            tempo: project.tempo
        )
        
        // Track state changes for debugging (no console output)
        if lastStartBeat != playbackStartBeat {
            let position = PlaybackPosition(beats: currentBeat, timeSignature: project.timeSignature, tempo: project.tempo)
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
    /// FORMULA: currentBeat = startBeat + (elapsedSeconds * (tempo / 60.0))
    /// 
    /// This method is nonisolated because it's a pure calculation with no state access,
    /// making it safe to call from both MainActor and audio thread contexts.
    /// 
    /// - Parameters:
    ///   - startBeat: The beat position where playback started
    ///   - startWallTime: The wall-clock time when playback started (from CACurrentMediaTime())
    ///   - currentWallTime: The current wall-clock time (from CACurrentMediaTime())
    ///   - tempo: The current tempo in BPM
    /// - Returns: The current beat position
    nonisolated internal func calculateCurrentBeat(startBeat: Double, startWallTime: TimeInterval, currentWallTime: TimeInterval, tempo: Double) -> Double {
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
    /// Jump to a specific beat position during playback (thread-safe)
    /// 
    /// BUG FIX (Issue #47): Cycle loop jumps now use seamless pre-scheduled audio
    /// instead of stop/start sequence which caused audible gaps.
    /// 
    /// CRITICAL PROBLEM (before fix):
    /// - Stop playback → clears all scheduled audio buffers
    /// - Restart playback → schedules new audio from scratch
    /// - Gap of silence during the stop/start transition
    /// - Audible click or discontinuity at loop boundary
    /// 
    /// SOLUTION:
    /// For cycle jumps, we rely on pre-scheduled iterations that are already
    /// queued in the AVAudioPlayerNode. We only update timing state and position,
    /// but DON'T stop/restart the player nodes.
    /// 
    /// PROFESSIONAL STANDARD:
    /// - Logic Pro: Pre-schedules 2-3 cycle iterations ahead
    /// - Pro Tools: Uses "loop cache" to avoid gaps
    /// - Ableton Live: Seamless looping with pre-scheduled blocks
    /// 
    /// SEAMLESS CYCLE LOOP ARCHITECTURE:
    /// 1. Audio tracks pre-schedule 2 iterations ahead (scheduleCycleAware)
    /// 2. On cycle jump, player nodes are ALREADY playing future iterations
    /// 3. We only update timing state to reflect the new position
    /// 4. No stop/start → no gap → seamless loop
    /// 
    /// NON-CYCLE JUMPS:
    /// For regular seeks (not cycle jumps), we still need stop/start because
    /// the pre-scheduled audio is for the wrong position.
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
        
        // BUG FIX (Issue #47): For cycle jumps, DON'T stop/restart audio
        // Audio tracks have already pre-scheduled multiple iterations ahead.
        // Stopping would clear these buffers and cause an audible gap.
        // 
        // The pre-scheduled audio is already playing, we just updated the timing
        // state above so position tracking reflects the new location.
        // 
        // MIDI and metronome were notified via onCycleJump above and can handle
        // the jump independently (they don't use pre-scheduled buffers).
        //
        // NOTE: This assumes we're jumping to the cycle start beat. For jumps
        // to arbitrary positions (non-cycle), we would need stop/restart.
        let isCycleJump = isCycleEnabled && abs(targetBeat - cycleStartBeat) < 0.001
        
        if !isCycleJump {
            // Not a cycle jump - need to stop and reschedule for new position
            onStopPlayback()
            onStartPlayback(targetBeat)
        }
        // else: Cycle jump - audio already pre-scheduled, no action needed
        
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
