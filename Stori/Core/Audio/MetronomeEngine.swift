//
//  MetronomeEngine.swift
//  Stori
//
//  Professional-grade metronome engine with sample-accurate scheduling
//  Shares the DAW's AVAudioEngine for perfect sync with all audio
//
//  Architecture (ChatGPT-informed):
//  - One shared AVAudioEngine (one clock)
//  - Nodes installed ONCE, before engine starts
//  - Clicks scheduled using AVAudioTime (sample-accurate)
//  - Timer only fills the scheduling queue, not the clock
//

import Foundation
import AVFoundation
import Combine
import Observation

// MARK: - Metronome Engine

/// Professional metronome engine with sample-accurate scheduling
///
/// Key principles:
/// 1. Shares the DAW's AVAudioEngine (single audio clock)
/// 2. Nodes attached/connected once, before engine starts
/// 3. Clicks scheduled at precise sample times using AVAudioTime
/// 4. A lightweight timer fills the scheduling queue (not the clock)
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class MetronomeEngine {
    
    // MARK: - Observable State
    
    /// Whether metronome is enabled (will click when transport plays)
    var isEnabled: Bool = false {
        didSet {
            if !isEnabled && isPlaying {
                stopPlaying()
            }
        }
    }
    
    /// Metronome volume (0.0 - 1.0)
    var volume: Float = 0.7 {
        didSet {
            metronomeMixer?.outputVolume = volume
        }
    }
    
    /// Current beat being played (1-based, for UI visualization)
    private(set) var currentBeat: Int = 1
    
    /// Flash state for UI beat indicator
    private(set) var beatFlash: Bool = false
    
    /// Whether count-in is enabled
    var countInEnabled: Bool = false
    
    /// Number of count-in bars
    var countInBars: Int = 1
    
    /// Project tempo (BPM) - synced from project
    var tempo: Double = 120.0
    
    /// Time signature numerator (beats per bar)
    var beatsPerBar: Int = 4
    
    // MARK: - Audio Nodes (ignored for observation)
    
    @ObservationIgnored
    private var clickPlayer: AVAudioPlayerNode?
    @ObservationIgnored
    private(set) var metronomeMixer: AVAudioMixerNode?
    
    // MARK: - Click Buffers
    
    @ObservationIgnored
    private var accentBuffer: AVAudioPCMBuffer?
    @ObservationIgnored
    private var normalBuffer: AVAudioPCMBuffer?
    
    // MARK: - Engine Reference
    
    @ObservationIgnored
    private weak var avAudioEngine: AVAudioEngine?
    @ObservationIgnored
    private weak var dawAudioEngine: AudioEngineContext?
    @ObservationIgnored
    private weak var transportController: TransportController?
    @ObservationIgnored
    private weak var midiScheduler: SampleAccurateMIDIScheduler?
    
    // MARK: - Scheduling State (ignored for observation)
    
    @ObservationIgnored
    private var isInstalled: Bool = false
    @ObservationIgnored
    private var isPlaying: Bool = false
    @ObservationIgnored
    private var sampleRate: Double = 48000
    
    @ObservationIgnored
    private var nextClickSampleTime: AVAudioFramePosition = 0
    
    @ObservationIgnored
    private var transportStartSampleTime: AVAudioFramePosition = 0
    
    @ObservationIgnored
    private var fillTimer: DispatchSourceTimer?
    
    @ObservationIgnored
    private var beatFlashTask: Task<Void, Never>?
    
    @ObservationIgnored
    private let lookaheadSeconds: Double = 0.5
    
    @ObservationIgnored
    private var lastPlayedBeatIndex: Int = -1
    
    @ObservationIgnored
    private let accentFrequency: Float = 1500
    @ObservationIgnored
    private let normalFrequency: Float = 1000
    @ObservationIgnored
    private let clickDuration: Double = 0.015
    
    // MARK: - Initialization
    
    init() {
        // Nodes will be installed by AudioEngine before it starts
    }
    
    // MARK: - Installation (called by AudioEngine during setup)
    
    /// Install metronome nodes into the DAW's audio engine
    /// MUST be called before engine.start() and only once
    func install(into engine: AVAudioEngine, dawMixer: AVAudioMixerNode, audioEngine: AudioEngineContext, transportController: TransportController, midiScheduler: SampleAccurateMIDIScheduler? = nil) {
        // Idempotent: only install once
        guard !isInstalled else { return }
        
        self.avAudioEngine = engine
        self.dawAudioEngine = audioEngine
        self.transportController = transportController
        self.midiScheduler = midiScheduler
        
        // Create nodes
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        
        // Attach to engine
        engine.attach(player)
        engine.attach(mixer)
        
        // Single source of truth: engine output node input format (device/processing rate)
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        let finalFormat: AVAudioFormat
        if deviceFormat.sampleRate > 0 && deviceFormat.channelCount > 0 {
            finalFormat = deviceFormat
        } else {
            self.sampleRate = 48000
            finalFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        }
        self.sampleRate = finalFormat.sampleRate
        
        // Connect: player → metronome mixer → DAW mixer
        // The DAW mixer (sharedMixer) feeds into masterEQ → outputNode
        engine.connect(player, to: mixer, format: finalFormat)
        engine.connect(mixer, to: dawMixer, format: finalFormat)
        
        // Set volume
        mixer.outputVolume = volume
        
        // Store references
        self.clickPlayer = player
        self.metronomeMixer = mixer
        
        // Generate click sounds at the correct sample rate and format
        generateClickSounds(format: finalFormat)
        
        isInstalled = true
    }
    
    /// Reconnect metronome nodes after engine.reset() or track connections disconnect them
    /// Called by AudioEngine after graph mutations
    func reconnectNodes(dawMixer: AVAudioMixerNode) {
        guard isInstalled,
              let engine = avAudioEngine,
              let player = clickPlayer,
              let metroMix = metronomeMixer else { return }
        
        // Get device format
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        let format: AVAudioFormat
        if deviceFormat.sampleRate > 0 && deviceFormat.channelCount > 0 {
            format = deviceFormat
        } else {
            format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        }
        
        // BUG FIX (Issue #51): Update sample rate when device changes
        // This ensures metronome timing calculations use the correct device sample rate
        self.sampleRate = format.sampleRate
        
        // BUG FIX (Issue #51): Regenerate click sounds at new sample rate
        // Click buffers contain sample data at specific sample rate and must be regenerated
        generateClickSounds(format: format)
        
        // Nodes are still attached after reset, just disconnected
        // Reconnect: player → metronome mixer → DAW mixer
        engine.connect(player, to: metroMix, format: format)
        engine.connect(metroMix, to: dawMixer, format: format)
    }
    
    /// Prepare the player node for playback (called after engine starts)
    /// This starts the player node so it's ready to receive scheduled buffers
    func preparePlayerNode() {
        guard let player = clickPlayer, player.engine != nil else { return }
        if !player.isPlaying {
            do {
                try tryObjC { player.play() }
            } catch {
                // play() threw ObjC exception - engine may not be fully ready
            }
        }
    }
    
    // MARK: - Click Sound Generation
    
    private func generateClickSounds(format: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(clickDuration * sampleRate)
        let channelCount = Int(format.channelCount)
        
        // Generate accent click (higher pitched, louder)
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
            buffer.frameLength = frameCount
            
            for channel in 0..<channelCount {
                let data = buffer.floatChannelData![channel]
                for frame in 0..<Int(frameCount) {
                    let time = Float(frame) / Float(sampleRate)
                    let envelope = generateClickEnvelope(time: time, duration: Float(clickDuration))
                    let sample = sin(2.0 * .pi * accentFrequency * time) * envelope
                    data[frame] = sample
                }
            }
            accentBuffer = buffer
        }
        
        // Generate normal click (lower pitched, slightly softer)
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
            buffer.frameLength = frameCount
            
            for channel in 0..<channelCount {
                let data = buffer.floatChannelData![channel]
                for frame in 0..<Int(frameCount) {
                    let time = Float(frame) / Float(sampleRate)
                    let envelope = generateClickEnvelope(time: time, duration: Float(clickDuration)) * 0.7
                    let sample = sin(2.0 * .pi * normalFrequency * time) * envelope
                    data[frame] = sample
                }
            }
            normalBuffer = buffer
        }
    }
    
    private func generateClickEnvelope(time: Float, duration: Float) -> Float {
        let attackTime: Float = 0.001  // 1ms attack
        let decayTime = duration - attackTime
        
        if time < attackTime {
            return time / attackTime
        } else {
            let decayProgress = (time - attackTime) / decayTime
            return exp(-5.0 * decayProgress)
        }
    }
    
    // MARK: - Transport Control
    
    /// Called when DAW transport starts playing
    func onTransportPlay() {
        guard isEnabled, isInstalled else { return }
        startPlaying()
    }
    
    /// Called when DAW transport stops
    func onTransportStop() {
        stopPlaying()
        currentBeat = 1
        lastPlayedBeatIndex = -1
    }
    
    /// Called when DAW seeks to a new position
    func onTransportSeek(to beat: Double) {
        currentBeat = Int(beat.truncatingRemainder(dividingBy: Double(beatsPerBar))) + 1
        
        // If playing, reset scheduling
        if isPlaying {
            stopPlaying()
            startPlaying()
        }
    }
    
    // MARK: - Playback Control
    
    private func startPlaying() {
        guard !isPlaying, isInstalled,
              let player = clickPlayer,
              let engine = avAudioEngine,
              metronomeMixer != nil,
              accentBuffer != nil, normalBuffer != nil else { return }
        
        // Verify engine is running
        guard engine.isRunning else { return }
        
        // SAFETY: Verify player node is still attached to the engine graph.
        // During graph mutations (track add/remove, engine reset), nodes can
        // become detached. Calling stop()/play() on a detached node throws an
        // ObjC NSInternalInconsistencyException that Swift cannot catch.
        guard player.engine != nil else { return }
        
        isPlaying = true
        
        // Re-arm the player on transport play.
        // Wrapped in ObjC exception handler because stop()/play() are graph
        // operations that can throw NSException if the graph is being mutated
        // concurrently (e.g., by installMetronome or track node reconnection).
        do {
            try tryObjC {
                player.stop()   // Clear stale state
                player.play()   // Re-join current render timeline
            }
        } catch {
            // Graph operation failed - metronome won't play this time
            // The user can retry by toggling transport
            isPlaying = false
            return
        }
        player.prepare(withFrameCount: 2048)  // Reduce first-click glitches
        
        // Get current render time as our anchor
        if let renderTime = engine.outputNode.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: renderTime) {
            transportStartSampleTime = playerTime.sampleTime
            
            // Compute the next beat boundary using thread-safe atomic position
            let currentBeatPosition: Double
            if let transport = transportController {
                currentBeatPosition = transport.atomicBeatPosition
            } else {
                // Fallback: MainActor-isolated read (NOT safe from audio thread!)
                currentBeatPosition = dawAudioEngine?.currentPosition.beats ?? 0
            }
            
            nextClickSampleTime = computeNextBeatSampleTime(
                from: playerTime.sampleTime,
                currentBeat: currentBeatPosition
            )
            
            // CRITICAL FIX: Initialize lastPlayedBeatIndex to current beat
            // This prevents an immediate click when starting mid-beat
            // We only want to click when we CROSS a beat boundary
            lastPlayedBeatIndex = Int(floor(currentBeatPosition))
        } else {
            // Fallback: start from 0
            transportStartSampleTime = 0
            nextClickSampleTime = 0
            lastPlayedBeatIndex = 0
        }
        
        // Start the fill timer (just keeps the queue filled, NOT the clock)
        startFillTimer()
        
        // Note: Don't call fillScheduleQueue() here - let the timer handle it
        // This prevents the immediate double-click on play
    }
    
    private func stopPlaying() {
        isPlaying = false
        beatFlash = false
        
        // Cancel beat flash task
        beatFlashTask?.cancel()
        beatFlashTask = nil
        
        // Stop the fill timer
        fillTimer?.cancel()
        fillTimer = nil
        
        // Stop the player (guard against detached node)
        if let player = clickPlayer, player.engine != nil {
            do {
                try tryObjC { player.stop() }
            } catch {
                // stop() threw ObjC exception - node may already be stopped/detached
            }
        }
    }
    
    // MARK: - Sample-Accurate Scheduling
    
    /// Compute the sample time of the next beat boundary
    /// Uses shared scheduling context when available for perfect sync with MIDI
    private func computeNextBeatSampleTime(from currentSampleTime: AVAudioFramePosition, currentBeat: Double) -> AVAudioFramePosition {
        // Use shared scheduling context if available (for perfect sync with MIDI)
        let framesPerBeat: Int64
        if let scheduler = midiScheduler {
            let context = scheduler.schedulingContext
            framesPerBeat = context.samplesPerBeatInt64()
        } else {
            // Fallback: calculate from local tempo
            framesPerBeat = self.framesPerBeat()
        }
        
        // Find the next whole beat
        let nextWholeBeat = ceil(currentBeat)
        let beatsUntilNext = nextWholeBeat - currentBeat
        
        // Convert to frames
        let framesUntilNext = AVAudioFramePosition(beatsUntilNext * Double(framesPerBeat))
        
        return currentSampleTime + framesUntilNext
    }
    
    private func framesPerBeat() -> AVAudioFramePosition {
        // Use shared scheduling context if available
        if let scheduler = midiScheduler {
            let context = scheduler.schedulingContext
            return context.samplesPerBeatInt64()
        }
        
        // Fallback: calculate from local tempo
        let secondsPerBeat = 60.0 / tempo
        return AVAudioFramePosition((secondsPerBeat * sampleRate).rounded())
    }
    
    /// Keep the scheduling queue filled with upcoming clicks
    /// Uses timer-based beat detection (simpler, more reliable)
    private func fillScheduleQueue() {
        guard isPlaying, isInstalled,
              let player = clickPlayer,
              let accentBuf = accentBuffer,
              let normalBuf = normalBuffer,
              let dawEngine = dawAudioEngine,
              player.engine != nil else { return }
        
        // Ensure player is still playing
        if !player.isPlaying {
            do {
                try tryObjC { player.play() }
            } catch {
                // Can't restart player - skip this fill cycle
                return
            }
        }
        
        // Get current beat position from the DAW
        // Get current beat position from single source of truth
        let currentBeats: Double
        if let transport = transportController {
            currentBeats = transport.atomicBeatPosition
        } else {
            // Fallback: MainActor-isolated read (NOT safe from audio thread!)
            currentBeats = dawEngine.currentPosition.beats
        }
        
        // Calculate which beat index we're on (floor to get the beat we're currently in)
        let currentBeatIndex = Int(floor(currentBeats))
        
        // Check if we've moved to a new beat
        if currentBeatIndex != lastPlayedBeatIndex {
            lastPlayedBeatIndex = currentBeatIndex
            
            // Calculate beat within bar (0-based internally, 1-based for display)
            let beatInBar = currentBeatIndex % beatsPerBar
            currentBeat = beatInBar + 1
            
            // Play the appropriate click
            let isDownbeat = beatInBar == 0
            let buffer = isDownbeat ? accentBuf : normalBuf
            
            // Schedule buffer immediately
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            
            // Trigger visual feedback
            triggerBeatFlash()
        }
    }
    
    private func startFillTimer() {
        fillTimer?.cancel()
        
        // Timer fires every 50ms to keep the queue filled
        // This is NOT the clock - it just maintains the lookahead buffer
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        
        timer.setEventHandler { [weak self] in
            // THREAD SAFETY: Use DispatchQueue.main.async instead of Task { @MainActor }
            // Task creation can crash in swift_getObjectType when accessing weak self
            // Note: Timer is already on .main queue, but async is safer than Task
            DispatchQueue.main.async {
                self?.fillScheduleQueue()
            }
        }
        
        timer.resume()
        fillTimer = timer
    }
    
    // MARK: - Visual Feedback
    
    private func triggerBeatFlash() {
        beatFlash = true
        
        // Cancel any existing flash task to prevent memory issues on deinit
        beatFlashTask?.cancel()
        
        // Store the task so we can cancel it during cleanup
        beatFlashTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
            await MainActor.run {
                self.beatFlash = false
            }
        }
    }
    
    // MARK: - Count-In
    
    /// Perform count-in before recording starts
    /// Uses a DispatchSourceTimer for more accurate timing than Task.sleep
    func performCountIn() async {
        guard countInEnabled, isInstalled,
              let player = clickPlayer else { return }
        
        let beatInterval = 60.0 / tempo
        let totalBeats = countInBars * beatsPerBar
        
        // Re-arm player for count-in (ensure clean state)
        player.stop()
        player.play()
        player.prepare(withFrameCount: 2048)
        
        // Use a semaphore to synchronize async completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var beatCount = 0
            
            // Use DispatchSourceTimer for more accurate timing
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: beatInterval, leeway: .milliseconds(1))
            
            timer.setEventHandler { [weak self] in
                guard let self = self else {
                    timer.cancel()
                    continuation.resume()
                    return
                }
                
                beatCount += 1
                
                if beatCount <= totalBeats {
                    // Calculate which beat in the bar (1-indexed)
                    self.currentBeat = ((beatCount - 1) % self.beatsPerBar) + 1
                    let isDownbeat = self.currentBeat == 1
                    
                    // Schedule the click
                    if let buffer = isDownbeat ? self.accentBuffer : self.normalBuffer {
                        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                    }
                    
                    self.triggerBeatFlash()
                } else {
                    // Count-in complete
                    timer.cancel()
                    
                    // Don't stop player - let it continue for recording/playback
                    // The transport will take over scheduling
                    self.currentBeat = 1
                    self.lastPlayedBeatIndex = -1  // Reset so first beat of recording triggers
                    
                    continuation.resume()
                }
            }
            
            timer.resume()
        }
    }
    
    // MARK: - Public Controls
    
    func toggle() {
        isEnabled.toggle()
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Cancel async resources before implicit deinit
        // ASan detected double-free during swift_task_deinitOnExecutorImpl
        // Root cause: Untracked Task holding self reference during @MainActor class cleanup
        // See: https://github.com/cgcardona/Stori/issues/AudioEngine-MemoryBug
        
        // Note: Cannot access @MainActor properties in deinit, but these are @ObservationIgnored
        beatFlashTask?.cancel()
        fillTimer?.cancel()
    }
}
