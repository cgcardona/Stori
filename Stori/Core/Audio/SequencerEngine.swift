//
//  SequencerEngine.swift
//  Stori
//
//  MIDI-based Step Sequencer engine with internal sampler preview
//  Supports routing to MIDI tracks, multi-track output, and external devices
//

import Foundation
@preconcurrency import AVFoundation
import Combine

// MARK: - Sequencer Engine

@MainActor
@Observable
class SequencerEngine {
    
    // MARK: - Public Properties
    
    var pattern: StepPattern
    var playbackState: SequencerPlaybackState = .stopped
    var currentStep: Int = 0
    
    /// MIDI routing configuration
    var routing: SequencerRouting = .default
    
    /// Callback for MIDI events (used by AudioEngine to route to tracks)
    var onMIDIEvent: ((SequencerMIDIEvent) -> Void)?
    
    /// Callback for batch MIDI events (all events for current step)
    var onMIDIEvents: (([SequencerMIDIEvent]) -> Void)?
    
    /// Drum kit loader for sample-based playback (preview mode)
    let kitLoader = DrumKitLoader()
    
    /// Currently selected kit name
    var currentKitName: String {
        kitLoader.currentKit.name
    }
    
    /// Whether the sequencer is currently playing
    var isPlaying: Bool {
        playbackState == .playing
    }
    
    /// Currently selected target track for MIDI routing
    var targetTrackId: UUID? {
        get { routing.targetTrackId }
        set { routing.targetTrackId = newValue }
    }
    
    /// Current routing mode
    var routingMode: SequencerRoutingMode {
        get { routing.mode }
        set { routing.mode = newValue }
    }
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var mixer: AVAudioMixerNode?
    private var stepTimer: DispatchSourceTimer?
    private var drumPlayers: [DrumSoundType: DrumPlayer] = [:]
    
    // MARK: - Initialization
    
    init(tempo: Double = 120.0) {
        self.pattern = StepPattern.defaultDrumKit(tempo: tempo)
        setupAudioEngine()
        loadSavedPatterns()
        loadFavoritesFromUserDefaults()
        loadRecentsFromUserDefaults()
    }

    nonisolated deinit {}

    // Note: stepTimer cleanup happens via stop() or when the engine is deallocated
    // Cannot access @MainActor properties in deinit
    
    // MARK: - Audio Setup
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let mixerNode = AVAudioMixerNode()
        
        engine.attach(mixerNode)
        
        // Connect mixer to output
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: format)
        
        // Create players for each drum type (supports both samples and synthesis)
        for soundType in DrumSoundType.allCases {
            let player = DrumPlayer(soundType: soundType)
            player.attach(to: engine, mixer: mixerNode, format: format)
            drumPlayers[soundType] = player
        }
        
        // Start the engine
        do {
            try engine.start()
        } catch {
        }
        
        self.audioEngine = engine
        self.mixer = mixerNode
        
        // Load samples from the default kit into drum players
        updatePlayersWithCurrentKit()
    }
    
    // MARK: - Kit Selection
    
    /// Select a drum kit
    func selectKit(_ kit: DrumKit) async {
        await kitLoader.selectKit(kit)
        updatePlayersWithCurrentKit()
    }
    
    /// Update all players with samples from current kit
    private func updatePlayersWithCurrentKit() {
        for (soundType, player) in drumPlayers {
            if let buffer = kitLoader.buffer(for: soundType) {
                player.setSampleBuffer(buffer)
            } else {
                player.clearSampleBuffer() // Fall back to synthesis
            }
        }
    }
    
    /// Get current pattern as NxM grid for visualization (16 rows × steps columns)
    func currentPatternGrid() -> [[Bool]] {
        var grid: [[Bool]] = []
        
        // Create rows (one for each lane/drum - typically 16)
        for lane in pattern.lanes {
            var row: [Bool] = []
            // Create columns (one for each step - 8, 16, or 32)
            for step in 0..<pattern.steps {
                row.append(lane.stepVelocities[step] != nil)
            }
            grid.append(row)
        }
        
        return grid
    }
    
    // MARK: - Transport Controls
    
    /// Start playback
    func play() {
        guard playbackState != .playing else { return }
        
        playbackState = .playing
        
        // Start from current step
        startStepTimer()
        
        // Trigger first step immediately
        triggerCurrentStep()
    }
    
    /// Stop playback and reset to beginning
    func stop() {
        playbackState = .stopped
        stepTimer?.cancel()
        stepTimer = nil
        currentStep = 0
    }
    
    /// Pause playback (keep current position)
    func pause() {
        guard playbackState == .playing else { return }
        playbackState = .paused
        stepTimer?.cancel()
        stepTimer = nil
    }
    
    /// Reset to beginning without stopping
    func reset() {
        currentStep = 0
    }
    
    // MARK: - Step Timer
    
    private func startStepTimer() {
        stepTimer?.cancel()
        
        let stepDuration = pattern.stepDuration
        let timer = DispatchSource.makeTimerSource(queue: .main)
        
        timer.schedule(
            deadline: .now() + stepDuration,
            repeating: stepDuration,
            leeway: .milliseconds(1)
        )
        
        timer.setEventHandler { [weak self] in
            // THREAD SAFETY: Use DispatchQueue.main.async instead of Task { @MainActor }
            // Task creation can crash in swift_getObjectType when accessing weak self
            DispatchQueue.main.async {
                self?.advanceStep()
            }
        }
        
        timer.resume()
        stepTimer = timer
    }
    
    private func advanceStep() {
        currentStep = (currentStep + 1) % pattern.steps
        triggerCurrentStep()
    }
    
    // MARK: - Step Triggering (MIDI-Based)
    
    private func triggerCurrentStep() {
        // Check for any solo'd lanes
        let hasSolo = pattern.lanes.contains { $0.isSolo }
        
        // Collect MIDI events for this step
        var midiEvents: [SequencerMIDIEvent] = []
        
        for lane in pattern.lanes {
            // Skip if muted or if there's a solo and this isn't it
            if lane.isMuted { continue }
            if hasSolo && !lane.isSolo { continue }
            
            // Skip if this sound type has no sample loaded (kit doesn't include it)
            if !kitLoader.hasSample(for: lane.soundType) { continue }
            
            // Check if this step is active and get its velocity
            if let stepVelocity = lane.velocity(for: currentStep) {
                // Apply probability - check if step should play
                let probability = lane.probability(for: currentStep)
                if probability < 1.0 {
                    let roll = Float.random(in: 0...1)
                    if roll > probability {
                        continue  // Skip this step based on probability
                    }
                }
                
                // Apply velocity humanization
                var finalVelocity = stepVelocity * lane.volume
                if pattern.humanizeVelocity > 0 {
                    let variation = Float.random(in: -0.2...0.2) * Float(pattern.humanizeVelocity)
                    finalVelocity = max(0.1, min(1.0, finalVelocity * (1 + variation)))
                }
                
                // Generate MIDI event
                let midiEvent = SequencerMIDIEvent.from(
                    lane: lane,
                    step: currentStep,
                    stepVelocity: finalVelocity,
                    totalSteps: pattern.steps
                )
                midiEvents.append(midiEvent)
                
                // Send individual MIDI event callback
                if routing.shouldSendMIDI {
                    onMIDIEvent?(midiEvent)
                }
                
                // Trigger internal sampler if in preview mode
                if routing.shouldPlayInternally {
                    triggerInternalSound(for: lane, velocity: finalVelocity)
                }
            }
        }
        
        // Send batch MIDI events callback (for efficient routing)
        if !midiEvents.isEmpty && routing.shouldSendMIDI {
            onMIDIEvents?(midiEvents)
        }
    }
    
    /// Trigger internal sampler sound (preview mode)
    private func triggerInternalSound(for lane: SequencerLane, velocity: Float) {
        guard let player = drumPlayers[lane.soundType] else { return }
        player.trigger(velocity: velocity)
    }
    
    // MARK: - MIDI Event Generation
    
    /// Generate all MIDI events for the current pattern (for export or preview)
    func generatePatternMIDIEvents(loops: Int = 1) -> [SequencerMIDIEvent] {
        var events: [SequencerMIDIEvent] = []
        let hasSolo = pattern.lanes.contains { $0.isSolo }
        
        for loopIndex in 0..<loops {
            let loopOffset = Double(loopIndex * pattern.steps) * 0.25  // 16th notes
            
            for lane in pattern.lanes {
                // Skip if muted or if there's a solo and this isn't it
                if lane.isMuted { continue }
                if hasSolo && !lane.isSolo { continue }
                
                // Skip if this sound type has no sample loaded (kit doesn't include it)
                if !kitLoader.hasSample(for: lane.soundType) { continue }
                
                for step in lane.activeSteps {
                    guard let stepVelocity = lane.velocity(for: step) else { continue }
                    
                    var event = SequencerMIDIEvent.from(
                        lane: lane,
                        step: step,
                        stepVelocity: stepVelocity * lane.volume,
                        totalSteps: pattern.steps
                    )
                    
                    // Adjust timestamp for loop offset
                    if loopOffset > 0 {
                        event = SequencerMIDIEvent(
                            note: event.note,
                            velocity: event.velocity,
                            channel: event.channel,
                            timestamp: event.timestamp + loopOffset,
                            duration: event.duration,
                            laneId: event.laneId,
                            soundType: event.soundType
                        )
                    }
                    
                    events.append(event)
                }
            }
        }
        
        // Sort by timestamp
        return events.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Routing Configuration
    
    /// Set routing mode
    func setRoutingMode(_ mode: SequencerRoutingMode) {
        routing.mode = mode
    }
    
    /// Set target track for single-track routing
    func setTargetTrack(_ trackId: UUID?) {
        routing.targetTrackId = trackId
        if trackId != nil && routing.mode == .preview {
            // Auto-switch to single track mode when a track is selected
            routing.mode = .singleTrack
        }
    }
    
    /// Set per-lane routing for multi-track mode
    func setLaneRouting(laneId: UUID, trackId: UUID?) {
        if let trackId = trackId {
            routing.perLaneRouting[laneId] = trackId
        } else {
            routing.perLaneRouting.removeValue(forKey: laneId)
        }
    }
    
    /// Get target track for a specific lane
    func targetTrack(for laneId: UUID) -> UUID? {
        switch routing.mode {
        case .preview:
            return nil
        case .singleTrack:
            return routing.targetTrackId
        case .multiTrack:
            return routing.perLaneRouting[laneId] ?? routing.targetTrackId
        case .external:
            return nil
        }
    }
    
    // MARK: - Pattern Editing
    
    /// Toggle a step on/off
    func toggleStep(laneId: UUID, step: Int, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture state before mutation
        let wasEnabled = pattern.lanes[index].stepVelocities[step] != nil
        let oldVelocity = pattern.lanes[index].stepVelocities[step]
        
        // Perform mutation
        pattern.lanes[index].toggleStep(step)
        
        // Register undo
        if registerUndo {
            UndoService.shared.registerToggleStep(laneId: laneId, step: step, wasEnabled: wasEnabled, oldVelocity: oldVelocity, sequencer: self)
        }
    }
    
    /// Set step state directly
    func setStep(laneId: UUID, step: Int, active: Bool, velocity: Float = 0.8, registerUndo: Bool = false) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture state before mutation (only if registering undo)
        let wasEnabled = pattern.lanes[index].stepVelocities[step] != nil
        let oldVelocity = pattern.lanes[index].stepVelocities[step]
        
        // Perform mutation
        if active {
            pattern.lanes[index].setStep(step, velocity: velocity)
        } else {
            pattern.lanes[index].stepVelocities.removeValue(forKey: step)
        }
        
        // Register undo (only if there's an actual change and undo is requested)
        if registerUndo && wasEnabled != active {
            UndoService.shared.registerToggleStep(laneId: laneId, step: step, wasEnabled: wasEnabled, oldVelocity: oldVelocity, sequencer: self)
        }
    }
    
    /// Set velocity for a specific step
    func setStepVelocity(laneId: UUID, step: Int, velocity: Float) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        if pattern.lanes[index].stepVelocities[step] != nil {
            pattern.lanes[index].setStep(step, velocity: velocity)
        }
    }
    
    /// Adjust velocity for a step (relative change)
    func adjustStepVelocity(laneId: UUID, step: Int, delta: Float, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old velocity before mutation
        let oldVelocity = pattern.lanes[index].stepVelocities[step] ?? 0.8
        
        // Perform mutation
        pattern.lanes[index].adjustVelocity(for: step, delta: delta)
        
        // Get new velocity after mutation
        let newVelocity = pattern.lanes[index].stepVelocities[step] ?? 0.8
        
        // Register undo (only if there's an actual change)
        if registerUndo && abs(oldVelocity - newVelocity) > 0.001 {
            UndoService.shared.registerStepVelocityChange(laneId: laneId, step: step, oldVelocity: oldVelocity, newVelocity: newVelocity, sequencer: self)
        }
    }
    
    /// Adjust probability for a step
    func adjustStepProbability(laneId: UUID, step: Int, delta: Float, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old probability before mutation
        let oldProbability = pattern.lanes[index].stepProbabilities[step] ?? 1.0
        
        // Perform mutation
        pattern.lanes[index].adjustProbability(for: step, delta: delta)
        
        // Get new probability after mutation
        let newProbability = pattern.lanes[index].stepProbabilities[step] ?? 1.0
        
        // Register undo (only if there's an actual change)
        if registerUndo && abs(oldProbability - newProbability) > 0.001 {
            UndoService.shared.registerStepProbabilityChange(laneId: laneId, step: step, oldProbability: oldProbability, newProbability: newProbability, sequencer: self)
        }
    }
    
    /// Clear all steps in a lane
    func clearLane(laneId: UUID, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old state before clearing
        let oldVelocities = pattern.lanes[index].stepVelocities
        let oldProbabilities = pattern.lanes[index].stepProbabilities
        
        // Only register undo if there's something to clear
        if registerUndo && !oldVelocities.isEmpty {
            UndoService.shared.registerClearLane(laneId: laneId, oldStepVelocities: oldVelocities, oldStepProbabilities: oldProbabilities, sequencer: self)
        }
        
        // Perform mutation
        pattern.lanes[index].clearAllSteps()
    }
    
    /// Clear entire pattern - creates a fresh pattern with new ID
    func clearPattern(registerUndo: Bool = true) {
        // Capture old pattern before clearing
        let oldPattern = pattern
        
        // Register undo
        if registerUndo {
            UndoService.shared.registerClearPattern(oldPattern: oldPattern, sequencer: self)
        }
        
        // Create a completely new pattern to ensure clean slate
        // Preserve tempo and step count from current pattern
        pattern = StepPattern(
            id: UUID(),
            name: "New Pattern",
            steps: pattern.steps,
            lanes: SequencerLane.defaultDrumKit(),
            tempo: pattern.tempo,
            swing: 0.0,
            sourceFilename: nil
        )
    }
    
    /// Toggle mute for a lane
    func toggleMute(laneId: UUID, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old state
        let wasMuted = pattern.lanes[index].isMuted
        
        // Perform mutation
        pattern.lanes[index].isMuted.toggle()
        
        // Register undo
        if registerUndo {
            UndoService.shared.registerLaneMuteToggle(laneId: laneId, wasMuted: wasMuted, sequencer: self)
        }
    }
    
    /// Toggle solo for a lane
    func toggleSolo(laneId: UUID, registerUndo: Bool = true) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old state
        let wasSolo = pattern.lanes[index].isSolo
        
        // Perform mutation
        pattern.lanes[index].isSolo.toggle()
        
        // Register undo
        if registerUndo {
            UndoService.shared.registerLaneSoloToggle(laneId: laneId, wasSolo: wasSolo, sequencer: self)
        }
    }
    
    /// Set lane volume
    func setLaneVolume(laneId: UUID, volume: Float, registerUndo: Bool = true, oldVolume: Float? = nil) {
        guard let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        
        // Capture old volume (use provided value for drag-end registration)
        let capturedOldVolume = oldVolume ?? pattern.lanes[index].volume
        let newVolume = max(0, min(1, volume))
        
        // Perform mutation
        pattern.lanes[index].volume = newVolume
        
        // Register undo (only if significant change)
        if registerUndo && abs(capturedOldVolume - newVolume) > 0.001 {
            UndoService.shared.registerLaneVolumeChange(laneId: laneId, from: capturedOldVolume, to: newVolume, sequencer: self)
        }
    }
    
    // MARK: - Tempo
    
    /// Update tempo (syncs with project)
    func setTempo(_ bpm: Double) {
        let wasPlaying = isPlaying
        
        // Stop and restart timer with new tempo
        if wasPlaying {
            stepTimer?.cancel()
            stepTimer = nil
        }
        
        pattern.tempo = bpm
        
        if wasPlaying {
            startStepTimer()
        }
        
    }
    
    /// Sync tempo from project
    func syncWithProject(_ projectManager: ProjectManager) {
        if let project = projectManager.currentProject {
            setTempo(project.tempo)
        }
    }
    
    // MARK: - Swing
    
    /// Set swing amount (0.0 = straight, 1.0 = full triplet feel)
    func setSwing(_ amount: Double, registerUndo: Bool = true, oldSwing: Double? = nil) {
        // Capture old swing (use provided value for drag-end registration)
        let capturedOldSwing = oldSwing ?? pattern.swing
        let newSwing = max(0, min(1, amount))
        
        // Perform mutation
        pattern.swing = newSwing
        
        // Register undo (only if significant change)
        if registerUndo && abs(capturedOldSwing - newSwing) > 0.001 {
            UndoService.shared.registerSwingChange(from: capturedOldSwing, to: newSwing, sequencer: self)
        }
    }
    
    /// Set humanization amount for timing variation
    func setHumanizeTiming(_ amount: Double, registerUndo: Bool = true, oldValue: Double? = nil) {
        // Capture old value (use provided value for drag-end registration)
        let capturedOldValue = oldValue ?? pattern.humanizeTiming
        let newValue = max(0, min(1, amount))
        
        // Perform mutation
        pattern.humanizeTiming = newValue
        
        // Register undo (only if significant change)
        if registerUndo && abs(capturedOldValue - newValue) > 0.001 {
            UndoService.shared.registerHumanizeTimingChange(from: capturedOldValue, to: newValue, sequencer: self)
        }
    }
    
    /// Set humanization amount for velocity variation
    func setHumanizeVelocity(_ amount: Double, registerUndo: Bool = true, oldValue: Double? = nil) {
        // Capture old value (use provided value for drag-end registration)
        let capturedOldValue = oldValue ?? pattern.humanizeVelocity
        let newValue = max(0, min(1, amount))
        
        // Perform mutation
        pattern.humanizeVelocity = newValue
        
        // Register undo (only if significant change)
        if registerUndo && abs(capturedOldValue - newValue) > 0.001 {
            UndoService.shared.registerHumanizeVelocityChange(from: capturedOldValue, to: newValue, sequencer: self)
        }
    }
    
    // MARK: - Pattern Length
    
    /// Change pattern length (8, 16, 32, 64 steps)
    /// Note: This only changes the visible/playable range - pattern data is preserved
    /// so switching 16 → 8 → 16 restores the original 16-step pattern
    func setPatternLength(_ steps: Int, registerUndo: Bool = true) {
        guard StepPattern.stepOptions.contains(steps) else {
            return
        }
        
        // Capture old length for undo
        let oldLength = pattern.steps
        
        // Skip if no change
        guard oldLength != steps else { return }
        
        let wasPlaying = isPlaying
        if wasPlaying { stop() }
        
        // Simply change the step count - all step data is preserved in the dictionary
        // The UI and playback will only use steps 0..<pattern.steps
        pattern.steps = steps
        
        // Ensure current step is within bounds
        if currentStep >= steps {
            currentStep = 0
        }
        
        // Register undo
        if registerUndo {
            UndoService.shared.registerPatternLengthChange(from: oldLength, to: steps, sequencer: self)
        }
    }
    
    // MARK: - Copy/Paste
    
    /// Clipboard for lane copying
    private static var laneClipboard: [Int: Float]?
    private static var patternClipboard: [[Int: Float]]?
    
    /// Copy a lane's steps to clipboard
    func copyLane(laneId: UUID) {
        guard let lane = pattern.lanes.first(where: { $0.id == laneId }) else { return }
        SequencerEngine.laneClipboard = lane.copySteps()
    }
    
    /// Paste clipboard to a lane
    func pasteLane(laneId: UUID) {
        guard let clipboard = SequencerEngine.laneClipboard,
              let index = pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
        pattern.lanes[index].pasteSteps(clipboard)
    }
    
    /// Copy entire pattern
    func copyPattern() {
        SequencerEngine.patternClipboard = pattern.lanes.map { $0.stepVelocities }
    }
    
    /// Paste entire pattern
    func pastePattern() {
        guard let clipboard = SequencerEngine.patternClipboard else { return }
        for (index, steps) in clipboard.enumerated() where index < pattern.lanes.count {
            pattern.lanes[index].stepVelocities = steps
        }
    }
    
    /// Check if clipboard has content
    var hasLaneClipboard: Bool {
        SequencerEngine.laneClipboard != nil
    }
    
    var hasPatternClipboard: Bool {
        SequencerEngine.patternClipboard != nil
    }
    
    // MARK: - Preview Sound
    
    /// Preview a drum sound (for auditioning)
    func previewSound(_ soundType: DrumSoundType) {
        // Don't preview if kit doesn't have this sound
        guard kitLoader.hasSample(for: soundType) else { return }
        guard let player = drumPlayers[soundType] else { return }
        player.trigger(velocity: 0.8)
    }
    
    // MARK: - Export to Audio
    
    /// Renders the current pattern to an audio file
    /// - Parameter loops: Number of times to repeat the pattern (default 4 = 4 bars)
    /// - Returns: URL to the rendered audio file, or nil if failed
    func exportToAudio(loops: Int = 4) -> URL? {
        let sampleRate: Double = 48000
        let channels: AVAudioChannelCount = 2
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            return nil
        }
        
        // Calculate total duration
        let patternDuration = pattern.duration
        let totalDuration = patternDuration * Double(loops)
        let totalFrames = AVAudioFrameCount(totalDuration * sampleRate)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return nil
        }
        outputBuffer.frameLength = totalFrames
        
        // Clear the buffer
        if let channelData = outputBuffer.floatChannelData {
            for channel in 0..<Int(channels) {
                memset(channelData[channel], 0, Int(totalFrames) * MemoryLayout<Float>.size)
            }
        }
        
        // Generate drum sounds and mix them into the buffer
        let stepDuration = pattern.stepDuration
        let hasSolo = pattern.lanes.contains { $0.isSolo }
        
        
        var totalHitsGenerated = 0
        for loopIndex in 0..<loops {
            for stepIndex in 0..<pattern.steps {
                let stepTime = Double(loopIndex) * patternDuration + Double(stepIndex) * stepDuration
                let stepFrame = Int(stepTime * sampleRate)
                
                for lane in pattern.lanes {
                    // Skip muted or non-solo lanes
                    if lane.isMuted { continue }
                    if hasSolo && !lane.isSolo { continue }
                    
                    if lane.activeSteps.contains(stepIndex) {
                        // Generate and mix this drum sound
                        mixDrumSound(
                            soundType: lane.soundType,
                            velocity: lane.volume,
                            atFrame: stepFrame,
                            into: outputBuffer,
                            sampleRate: sampleRate
                        )
                        totalHitsGenerated += 1
                    }
                }
            }
        }
        
        
        // Check if buffer has actual audio data
        if let channelData = outputBuffer.floatChannelData {
            var maxAmplitude: Float = 0.0
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(outputBuffer.frameLength) {
                    maxAmplitude = max(maxAmplitude, abs(channelData[channel][frame]))
                }
            }
            if maxAmplitude == 0.0 {
            }
        }
        
        // Write to file
        // Sanitize filename: remove/replace characters that are invalid in file paths
        let sanitizedName = pattern.name
            .replacingOccurrences(of: "/", with: "-")  // Replace slashes with dashes (e.g., "7/8" → "7-8")
            .replacingOccurrences(of: " ", with: "_")   // Replace spaces with underscores
            .replacingOccurrences(of: ":", with: "-")   // Replace colons
            .replacingOccurrences(of: "?", with: "")    // Remove question marks
            .replacingOccurrences(of: "*", with: "")    // Remove asterisks
            .replacingOccurrences(of: "\"", with: "")   // Remove quotes
            .replacingOccurrences(of: "<", with: "")    // Remove less-than
            .replacingOccurrences(of: ">", with: "")    // Remove greater-than
            .replacingOccurrences(of: "|", with: "")    // Remove pipes
        let fileName = "\(sanitizedName)_\(Int(Date().timeIntervalSince1970)).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        TempFileManager.track(tempURL)
        // Use standard 24-bit PCM WAV format (universally supported)
        // AVAudioFile will automatically convert from the Float32 buffer
        // This is more reliable than trying to write Float32 directly to WAV
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        
        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            try audioFile.write(from: outputBuffer)
            return tempURL
        } catch {
            if let nsError = error as NSError? {
            }
            return nil
        }
    }
    
    // MARK: - MIDI Export
    
    /// Export the current pattern to a MIDI file
    /// - Parameters:
    ///   - loops: Number of times to loop the pattern (default 1)
    /// - Returns: URL of the exported MIDI file, or nil on failure
    func exportToMIDI(loops: Int = 1) -> URL? {
        let ticksPerQuarter: UInt16 = 480  // Standard MIDI resolution
        let tempo = pattern.tempo
        
        // Calculate ticks per step (16th notes = 1/4 of a quarter note)
        let ticksPerStep = Int(ticksPerQuarter) / 4
        
        // Default note duration (16th note length)
        let noteDuration = ticksPerStep
        
        // Collect all MIDI events
        var events: [(tick: Int, type: MIDIEventType)] = []
        
        let hasSolo = pattern.lanes.contains { $0.isSolo }
        
        for loopIndex in 0..<loops {
            let loopStartTick = loopIndex * pattern.steps * ticksPerStep
            
            for stepIndex in 0..<pattern.steps {
                let stepTick = loopStartTick + stepIndex * ticksPerStep
                
                for lane in pattern.lanes {
                    // Skip muted or non-solo lanes
                    if lane.isMuted { continue }
                    if hasSolo && !lane.isSolo { continue }
                    
                    if let velocity = lane.stepVelocities[stepIndex] {
                        let midiNote = lane.soundType.midiNote
                        let midiVelocity = UInt8(velocity * 127)
                        
                        // Note On
                        events.append((tick: stepTick, type: .noteOn(note: midiNote, velocity: midiVelocity)))
                        
                        // Note Off (after duration)
                        events.append((tick: stepTick + noteDuration, type: .noteOff(note: midiNote)))
                    }
                }
            }
        }
        
        // Sort events by tick
        events.sort { $0.tick < $1.tick }
        
        // Build MIDI file data
        var midiData = Data()
        
        // --- MIDI File Header ---
        // "MThd" chunk
        midiData.append(contentsOf: [0x4D, 0x54, 0x68, 0x64])  // "MThd"
        midiData.append(contentsOf: [0x00, 0x00, 0x00, 0x06])  // Header length (6 bytes)
        midiData.append(contentsOf: [0x00, 0x00])              // Format type 0 (single track)
        midiData.append(contentsOf: [0x00, 0x01])              // Number of tracks (1)
        midiData.append(contentsOf: UInt16(ticksPerQuarter).bigEndianBytes)  // Ticks per quarter
        
        // --- Track Chunk ---
        var trackData = Data()
        
        // Tempo meta event (at tick 0)
        let microsecondsPerBeat = Int(60_000_000 / tempo)
        trackData.append(0x00)  // Delta time 0
        trackData.append(contentsOf: [0xFF, 0x51, 0x03])  // Tempo meta event
        trackData.append(contentsOf: [
            UInt8((microsecondsPerBeat >> 16) & 0xFF),
            UInt8((microsecondsPerBeat >> 8) & 0xFF),
            UInt8(microsecondsPerBeat & 0xFF)
        ])
        
        // Convert events to track data with delta times
        var lastTick = 0
        for event in events {
            let deltaTick = event.tick - lastTick
            lastTick = event.tick
            
            // Write variable-length delta time
            trackData.append(contentsOf: variableLengthQuantity(deltaTick))
            
            // Write MIDI event
            switch event.type {
            case .noteOn(let note, let velocity):
                trackData.append(contentsOf: [0x99, note, velocity])  // Channel 10 (drums)
            case .noteOff(let note):
                trackData.append(contentsOf: [0x89, note, 0x00])      // Channel 10 (drums)
            }
        }
        
        // End of track meta event
        trackData.append(0x00)  // Delta time 0
        trackData.append(contentsOf: [0xFF, 0x2F, 0x00])  // End of track
        
        // "MTrk" chunk
        midiData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])  // "MTrk"
        midiData.append(contentsOf: UInt32(trackData.count).bigEndianBytes)  // Track length
        midiData.append(trackData)
        
        // Write to file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(pattern.name)-\(UUID().uuidString.prefix(8)).mid")
        TempFileManager.track(tempURL)
        do {
            try midiData.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
    
    /// MIDI event types for export
    private enum MIDIEventType {
        case noteOn(note: UInt8, velocity: UInt8)
        case noteOff(note: UInt8)
    }
    
    /// Convert integer to MIDI variable-length quantity bytes
    private func variableLengthQuantity(_ value: Int) -> [UInt8] {
        var result: [UInt8] = []
        var v = value
        
        result.append(UInt8(v & 0x7F))
        v >>= 7
        
        while v > 0 {
            result.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        
        return result
    }
    
    // MARK: - Pattern Persistence
    
    /// Saved user patterns (loaded from disk)
    var savedPatterns: [StepPattern] = []
    
    /// Favorite preset names (persisted to UserDefaults)
    var favoritePresets: Set<String> = [] {
        didSet {
            saveFavoritesToUserDefaults()
        }
    }
    
    /// Recently used preset names (persisted to UserDefaults)
    var recentPresets: [String] = [] {
        didSet {
            saveRecentsToUserDefaults()
        }
    }
    
    private let maxRecentPresets = 10
    
    /// Toggle a preset as favorite
    func toggleFavorite(_ presetName: String) {
        if favoritePresets.contains(presetName) {
            favoritePresets.remove(presetName)
        } else {
            favoritePresets.insert(presetName)
        }
    }
    
    /// Add a preset to recent history
    func addToRecents(_ presetName: String) {
        // Remove if already exists
        recentPresets.removeAll { $0 == presetName }
        // Add to front
        recentPresets.insert(presetName, at: 0)
        // Keep only max count
        if recentPresets.count > maxRecentPresets {
            recentPresets = Array(recentPresets.prefix(maxRecentPresets))
        }
    }
    
    private func loadFavoritesFromUserDefaults() {
        if let saved = UserDefaults.standard.array(forKey: "SequencerFavoritePresets") as? [String] {
            favoritePresets = Set(saved)
        }
    }
    
    private func saveFavoritesToUserDefaults() {
        UserDefaults.standard.set(Array(favoritePresets), forKey: "SequencerFavoritePresets")
    }
    
    private func loadRecentsFromUserDefaults() {
        if let saved = UserDefaults.standard.array(forKey: "SequencerRecentPresets") as? [String] {
            recentPresets = saved
        }
    }
    
    private func saveRecentsToUserDefaults() {
        UserDefaults.standard.set(recentPresets, forKey: "SequencerRecentPresets")
    }
    
    /// Load all saved patterns from disk
    func loadSavedPatterns() {
        guard let patternsDir = userPatternsDirectory else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: patternsDir, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            var loaded: [StepPattern] = []
            for file in jsonFiles {
                if let data = try? Data(contentsOf: file),
                   var pattern = try? JSONDecoder().decode(StepPattern.self, from: data) {
                    // Store the actual filename for later deletion
                    pattern.sourceFilename = file.lastPathComponent
                    loaded.append(pattern)
                }
            }
            savedPatterns = loaded.sorted { $0.name < $1.name }
        } catch {
        }
    }
    
    /// Save the current pattern to disk
    /// Returns: .success if saved, .duplicateName if name already exists, .error for other failures
    func saveCurrentPattern() -> SavePatternResult {
        guard let patternsDir = userPatternsDirectory else { return .error }
        
        let saveName = pattern.name.isEmpty ? "Untitled Pattern" : pattern.name
        
        // Check for duplicate names (excluding the current pattern if it's an update)
        let isUpdate = pattern.sourceFilename != nil
        let conflictingPattern = savedPatterns.first { existingPattern in
            existingPattern.name == saveName && existingPattern.sourceFilename != pattern.sourceFilename
        }
        
        if conflictingPattern != nil {
            return .duplicateName
        }
        
        // Determine filename: use existing if updating, generate new if creating
        let filename: String
        if let existingFilename = pattern.sourceFilename {
            // Updating existing pattern - keep same filename
            filename = existingFilename
        } else {
            // New pattern - generate filename from name
            let safeFileName = saveName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            filename = "\(safeFileName).json"
        }
        
        let fileURL = patternsDir.appendingPathComponent(filename)
        
        // Create a copy with the final name and source filename
        var patternToSave = pattern
        patternToSave.name = saveName
        patternToSave.sourceFilename = filename
        
        do {
            let data = try JSONEncoder().encode(patternToSave)
            try data.write(to: fileURL)
            
            // Update current pattern's sourceFilename so future saves are updates
            pattern.sourceFilename = filename
            pattern.name = saveName
            
            // Reload patterns to include the new one
            loadSavedPatterns()
            return .success
        } catch {
            return .error
        }
    }
    
    /// Result of saving a pattern
    enum SavePatternResult {
        case success
        case duplicateName
        case error
    }
    
    /// Load a saved pattern (uses current project tempo)
    func loadPattern(_ pattern: StepPattern) {
        var loadedPattern = pattern
        // Set to current project tempo (tempo not stored in pattern JSON)
        loadedPattern.tempo = self.pattern.tempo
        self.pattern = loadedPattern
    }
    
    /// Delete a saved pattern
    func deletePattern(_ pattern: StepPattern) -> Bool {
        guard let patternsDir = userPatternsDirectory else { return false }
        
        // Use the stored source filename if available, otherwise fall back to sanitized name
        let filename = pattern.sourceFilename ?? {
            let safeFileName = pattern.name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            return "\(safeFileName).json"
        }()
        
        let fileURL = patternsDir.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            loadSavedPatterns()
            return true
        } catch {
            return false
        }
    }
    
    /// Directory for user patterns
    var userPatternsDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let patternsDir = appSupport.appendingPathComponent("Stori/Patterns")
        
        if !FileManager.default.fileExists(atPath: patternsDir.path) {
            try? FileManager.default.createDirectory(at: patternsDir, withIntermediateDirectories: true)
        }
        
        return patternsDir
    }
    
    /// Mix a drum sound into the output buffer at the specified frame position
    private func mixDrumSound(soundType: DrumSoundType, velocity: Float, atFrame startFrame: Int, into buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channels = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        
        // Only render if kit has this sound - no synthesized fallback
        guard let sampleBuffer = kitLoader.buffer(for: soundType),
              let sampleData = sampleBuffer.floatChannelData else {
            return  // Skip unavailable sounds
        }
        
        let sampleFrames = Int(sampleBuffer.frameLength)
        let sampleChannels = Int(sampleBuffer.format.channelCount)
        
        for frame in 0..<sampleFrames {
            let outputFrame = startFrame + frame
            guard outputFrame < totalFrames else { break }
            
            // Mix sample into output buffer
            for channel in 0..<channels {
                let sampleChannel = min(channel, sampleChannels - 1)
                let sample = sampleData[sampleChannel][frame] * velocity
                channelData[channel][outputFrame] += sample
            }
        }
    }
    
    
    private func drumSoundDuration(for soundType: DrumSoundType) -> Double {
        switch soundType {
        case .kick: return 0.3
        case .snare, .clap, .rim: return 0.2
        case .hihatClosed: return 0.1
        case .hihatOpen, .ride, .shaker, .tambourine: return 0.4
        case .tomLow, .tomMid, .tomHigh: return 0.25
        case .crash: return 0.8
        case .cowbell: return 0.15
        case .congaLow, .congaHigh: return 0.3
        }
    }
    
    private func synthesizeDrumSample(soundType: DrumSoundType, at t: Double, duration: Double) -> Double {
        let envelope = calculateExportEnvelope(soundType: soundType, at: t)
        
        switch soundType {
        case .kick:
            let pitchEnvelope = exp(-t * 30)
            let freq = 60 + 100 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.8
            
        case .snare:
            let noise = Double.random(in: -1...1) * 0.6
            let body = sin(2 * .pi * 180 * t) * 0.4
            return (noise + body) * envelope
            
        case .hihatClosed:
            let noise = Double.random(in: -1...1)
            return noise * envelope * 0.5
            
        case .hihatOpen:
            let noise = Double.random(in: -1...1)
            return noise * envelope * 0.4
            
        case .clap:
            let noise = Double.random(in: -1...1)
            let burstEnvelope = sin(.pi * t / 0.02).magnitude
            return noise * envelope * burstEnvelope * 0.6
            
        case .tomLow:
            let pitchEnvelope = exp(-t * 15)
            let freq = 80 + 40 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tomHigh:
            let pitchEnvelope = exp(-t * 18)
            let freq = 150 + 50 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .crash:
            let noise = Double.random(in: -1...1)
            let shimmer = sin(2 * .pi * 4000 * t) * 0.2
            return (noise * 0.8 + shimmer) * envelope * 0.5
            
        case .ride:
            let tone = sin(2 * .pi * 5000 * t) * 0.3
            let noise = Double.random(in: -1...1) * 0.3
            return (tone + noise) * envelope * 0.4
            
        case .rim:
            let tone = sin(2 * .pi * 1000 * t)
            return tone * envelope * 0.6
            
        case .cowbell:
            let f1 = sin(2 * .pi * 560 * t)
            let f2 = sin(2 * .pi * 845 * t)
            return (f1 * 0.6 + f2 * 0.4) * envelope * 0.5
            
        case .shaker:
            let noise = Double.random(in: -1...1)
            let mod = (sin(2 * .pi * 30 * t) + 1) / 2
            return noise * envelope * mod * 0.4
            
        case .tomMid:
            let pitchEnvelope = exp(-t * 16)
            let freq = 110 + 45 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tambourine:
            let noise = Double.random(in: -1...1) * 0.5
            let jingle = sin(2 * .pi * 5500 * t) * 0.3 + sin(2 * .pi * 7200 * t) * 0.2
            return (noise + jingle) * envelope * 0.5
            
        case .congaLow:
            let pitchEnvelope = exp(-t * 12)
            let freq = 180 + 60 * pitchEnvelope
            let body = sin(2 * .pi * freq * t) * 0.7
            let slap = Double.random(in: -1...1) * exp(-t * 40) * 0.3
            return (body + slap) * envelope * 0.6
            
        case .congaHigh:
            let pitchEnvelope = exp(-t * 14)
            let freq = 250 + 80 * pitchEnvelope
            let body = sin(2 * .pi * freq * t) * 0.6
            let slap = Double.random(in: -1...1) * exp(-t * 50) * 0.4
            return (body + slap) * envelope * 0.6
        }
    }
    
    private func calculateExportEnvelope(soundType: DrumSoundType, at t: Double) -> Double {
        let attack: Double
        let decay: Double
        
        switch soundType {
        case .kick:
            attack = 0.005; decay = 8.0
        case .snare, .clap:
            attack = 0.002; decay = 12.0
        case .hihatClosed:
            attack = 0.001; decay = 25.0
        case .hihatOpen:
            attack = 0.001; decay = 5.0
        case .tomLow, .tomMid, .tomHigh:
            attack = 0.005; decay = 10.0
        case .crash:
            attack = 0.002; decay = 2.0
        case .ride:
            attack = 0.002; decay = 4.0
        case .rim:
            attack = 0.001; decay = 20.0
        case .cowbell:
            attack = 0.001; decay = 15.0
        case .shaker, .tambourine:
            attack = 0.01; decay = 6.0
        case .congaLow, .congaHigh:
            attack = 0.003; decay = 8.0
        }
        
        if t < attack {
            return t / attack
        }
        return exp(-decay * (t - attack))
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// @Observable + @MainActor classes can have implicit tasks from the Observation framework
    /// that cause memory corruption during deallocation if not properly cleaned up
}

// MARK: - Drum Player

/// Plays drum sounds using either loaded samples or synthesized fallback
private class DrumPlayer {
    let soundType: DrumSoundType
    private var playerNode: AVAudioPlayerNode?
    private var synthesizedBuffer: AVAudioPCMBuffer?
    private var sampleBuffer: AVAudioPCMBuffer?
    private var audioFormat: AVAudioFormat?
    
    /// Whether we're using a loaded sample (vs synthesis)
    var usingSample: Bool {
        sampleBuffer != nil
    }
    
    init(soundType: DrumSoundType) {
        self.soundType = soundType
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    func attach(to engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: format)
        
        // Pre-generate synthesized fallback sound
        self.audioFormat = format
        synthesizedBuffer = generateSynthesizedSound(format: format)
        
        self.playerNode = player
    }
    
    /// Set a sample buffer to use instead of synthesis
    func setSampleBuffer(_ buffer: AVAudioPCMBuffer) {
        #if DEBUG
        // Check if the loaded sample itself is clipping
        if let channelData = buffer.floatChannelData {
            var maxSample: Float = 0
            var clippedCount = 0
            
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = abs(channelData[channel][frame])
                    maxSample = max(maxSample, sample)
                    if sample > 0.99 {
                        clippedCount += 1
                    }
                }
            }
            
            if clippedCount > 0 {
                print("⚠️ DRUM SAMPLE \(soundType) CONTAINS CLIPPING: \(clippedCount) frames, max: \(maxSample)")
            }
        }
        #endif
        
        sampleBuffer = buffer
    }
    
    /// Clear the sample buffer to fall back to synthesis
    func clearSampleBuffer() {
        sampleBuffer = nil
    }
    
    /// Trigger the drum sound
    func trigger(velocity: Float) {
        guard let player = playerNode else { return }
        guard let engine = player.engine else { return }
        
        // Engine must be running
        guard engine.isRunning else { return }
        
        // Check if player has output connections
        let outputConnections = engine.outputConnectionPoints(for: player, outputBus: 0)
        guard !outputConnections.isEmpty else { return }
        
        // Prefer sample, fall back to synthesized
        guard let buffer = sampleBuffer ?? synthesizedBuffer else { return }
        
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.volume = velocity
        player.play()
    }
    
    // MARK: - Sound Synthesis (Fallback)
    
    private func generateSynthesizedSound(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration: Double
        
        // Different durations for different sounds
        switch soundType {
        case .kick:
            duration = 0.3
        case .snare, .clap, .rim:
            duration = 0.2
        case .hihatClosed:
            duration = 0.1
        case .hihatOpen, .ride, .shaker, .tambourine:
            duration = 0.4
        case .tomLow, .tomMid, .tomHigh:
            duration = 0.25
        case .crash:
            duration = 0.8
        case .cowbell:
            duration = 0.15
        case .congaLow, .congaHigh:
            duration = 0.3
        }
        
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // Generate the waveform based on sound type
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = synthesizeSample(at: t, duration: duration)
            
            // Write to all channels
            for channel in 0..<Int(format.channelCount) {
                channelData[channel][frame] = Float(sample)
            }
        }
        
        return buffer
    }
    
    private func synthesizeSample(at t: Double, duration: Double) -> Double {
        let envelope = calculateEnvelope(at: t)
        
        switch soundType {
        case .kick:
            let pitchEnvelope = exp(-t * 30)
            let freq = 60 + 100 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.8
            
        case .snare:
            let noise = Double.random(in: -1...1) * 0.6
            let body = sin(2 * .pi * 180 * t) * 0.4
            return (noise + body) * envelope
            
        case .hihatClosed:
            let noise = Double.random(in: -1...1)
            return noise * envelope * 0.5
            
        case .hihatOpen:
            let noise = Double.random(in: -1...1)
            return noise * envelope * 0.4
            
        case .clap:
            let noise = Double.random(in: -1...1)
            let burstEnvelope = sin(.pi * t / 0.02).magnitude
            return noise * envelope * burstEnvelope * 0.6
            
        case .tomLow:
            let pitchEnvelope = exp(-t * 15)
            let freq = 80 + 40 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tomHigh:
            let pitchEnvelope = exp(-t * 18)
            let freq = 150 + 50 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .crash:
            let noise = Double.random(in: -1...1)
            let shimmer = sin(2 * .pi * 4000 * t) * 0.2
            return (noise * 0.8 + shimmer) * envelope * 0.5
            
        case .ride:
            let tone = sin(2 * .pi * 5000 * t) * 0.3
            let noise = Double.random(in: -1...1) * 0.3
            return (tone + noise) * envelope * 0.4
            
        case .rim:
            let tone = sin(2 * .pi * 1000 * t)
            return tone * envelope * 0.6
            
        case .cowbell:
            let f1 = sin(2 * .pi * 560 * t)
            let f2 = sin(2 * .pi * 845 * t)
            return (f1 * 0.6 + f2 * 0.4) * envelope * 0.5
            
        case .shaker:
            let noise = Double.random(in: -1...1)
            let mod = (sin(2 * .pi * 30 * t) + 1) / 2
            return noise * envelope * mod * 0.4
            
        case .tomMid:
            // Mid tom - between low and high tom frequencies
            let pitchEnvelope = exp(-t * 16)
            let freq = 110 + 45 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tambourine:
            // Tambourine - metallic jingles with attack
            let noise = Double.random(in: -1...1) * 0.5
            let jingle = sin(2 * .pi * 5500 * t) * 0.3 + sin(2 * .pi * 7200 * t) * 0.2
            return (noise + jingle) * envelope * 0.5
            
        case .congaLow:
            // Low conga - warm, resonant thump
            let pitchEnvelope = exp(-t * 12)
            let freq = 180 + 60 * pitchEnvelope
            let body = sin(2 * .pi * freq * t) * 0.7
            let slap = Double.random(in: -1...1) * exp(-t * 40) * 0.3
            return (body + slap) * envelope * 0.6
            
        case .congaHigh:
            // High conga - brighter, more attack
            let pitchEnvelope = exp(-t * 14)
            let freq = 250 + 80 * pitchEnvelope
            let body = sin(2 * .pi * freq * t) * 0.6
            let slap = Double.random(in: -1...1) * exp(-t * 50) * 0.4
            return (body + slap) * envelope * 0.6
        }
    }
    
    private func calculateEnvelope(at t: Double) -> Double {
        let attack: Double
        let decay: Double
        
        switch soundType {
        case .kick:
            attack = 0.005; decay = 8.0
        case .snare, .clap:
            attack = 0.002; decay = 12.0
        case .hihatClosed:
            attack = 0.001; decay = 25.0
        case .hihatOpen:
            attack = 0.001; decay = 5.0
        case .tomLow, .tomMid, .tomHigh:
            attack = 0.005; decay = 10.0
        case .crash:
            attack = 0.002; decay = 2.0
        case .ride:
            attack = 0.002; decay = 4.0
        case .rim:
            attack = 0.001; decay = 20.0
        case .cowbell:
            attack = 0.001; decay = 15.0
        case .shaker, .tambourine:
            attack = 0.01; decay = 6.0
        case .congaLow, .congaHigh:
            attack = 0.003; decay = 8.0
        }
        
        if t < attack {
            return t / attack
        }
        return exp(-decay * (t - attack))
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// Even simple nested classes can have implicit tasks that cause memory corruption
}
