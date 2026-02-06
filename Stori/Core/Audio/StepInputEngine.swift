//
//  StepInputEngine.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Step input mode for entering notes one at a time via MIDI keyboard.
//  Advances automatically after each note is entered.
//
//  ARCHITECTURE: Beats-First
//  - All positions are in beats (musical time)
//

import Foundation

// MARK: - StepInputEngine

/// Engine for step-by-step MIDI note entry via keyboard.
/// All positions are in BEATS (musical time).
@MainActor
@Observable
class StepInputEngine {
    
    // MARK: - Properties
    
    /// Is step input mode active
    var isActive = false
    
    /// Current step position in the region (in beats)
    var stepPositionBeats: Double = 0
    
    /// Duration of each entered note
    var stepDuration: SnapResolution = .eighth
    
    /// Time signature for grid calculation (Issue #64). Defaults to 4/4.
    var timeSignature: TimeSignature = .fourFour
    
    /// Velocity for new notes (0-127)
    var velocity: UInt8 = 100
    
    /// Should auto-advance after each note
    var autoAdvance = true
    
    /// Should play note when entered
    var previewNote = true
    
    /// The region being edited
    var targetRegion: MIDIRegion?
    
    /// Currently held notes (for chords)
    var heldNotes: Set<UInt8> = []
    
    /// Chord input timeout (seconds) - notes pressed within this window form a chord
    var chordTimeout: TimeInterval = 0.1
    
    // MARK: - Private Properties
    
    private weak var midiDeviceManager: MIDIDeviceManager?
    private var onNotePreview: ((UInt8, UInt8) -> Void)?
    private var onNoteOff: ((UInt8) -> Void)?
    private var chordTimer: Timer?
    private var pendingChordNotes: [(pitch: UInt8, velocity: UInt8)] = []
    
    // MARK: - Callbacks
    
    /// Called when the region is modified
    var onRegionModified: ((MIDIRegion) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    /// Configure with MIDI device manager for input
    func configure(
        midiDeviceManager: MIDIDeviceManager,
        onNotePreview: @escaping (UInt8, UInt8) -> Void,
        onNoteOff: @escaping (UInt8) -> Void
    ) {
        self.midiDeviceManager = midiDeviceManager
        self.onNotePreview = onNotePreview
        self.onNoteOff = onNoteOff
    }
    
    // MARK: - Step Input Control
    
    /// Start step input on a region at a specific beat position
    func start(region: MIDIRegion, atBeat beat: Double) {
        targetRegion = region
        stepPositionBeats = max(0, beat)
        isActive = true
        heldNotes.removeAll()
        pendingChordNotes.removeAll()
        
        setupMIDICallbacks()
    }
    
    /// Stop step input mode
    func stop() {
        isActive = false
        heldNotes.removeAll()
        pendingChordNotes.removeAll()
        chordTimer?.invalidate()
        chordTimer = nil
        
        clearMIDICallbacks()
    }
    
    /// Toggle step input mode
    func toggle(region: MIDIRegion?, atBeat beat: Double) {
        if isActive {
            stop()
        } else if let region = region {
            start(region: region, atBeat: beat)
        }
    }
    
    // MARK: - Navigation
    
    /// Move to the next step position
    func advanceStep() {
        stepPositionBeats += stepDuration.stepDurationBeats(timeSignature: timeSignature)
    }
    
    /// Move to the previous step position
    func goBack() {
        stepPositionBeats = max(0, stepPositionBeats - stepDuration.stepDurationBeats(timeSignature: timeSignature))
    }
    
    /// Jump to a specific beat position
    func jumpTo(beat: Double) {
        stepPositionBeats = max(0, beat)
    }
    
    /// Insert a rest (advance without adding a note)
    func insertRest() {
        advanceStep()
    }
    
    // MARK: - Note Entry
    
    /// Manually enter a note at the current beat position
    func enterNote(pitch: UInt8, velocity: UInt8? = nil) {
        guard var region = targetRegion else { return }
        
        let noteVelocity = velocity ?? self.velocity
        
        let gridStep = stepDuration.stepDurationBeats(timeSignature: timeSignature)
        let note = MIDINote(
            id: UUID(),
            pitch: pitch,
            velocity: noteVelocity,
            startBeat: stepPositionBeats,
            durationBeats: gridStep,
            channel: 0
        )
        
        region.addNote(note)
        targetRegion = region
        onRegionModified?(region)
        
        // Preview the note
        if previewNote {
            onNotePreview?(pitch, noteVelocity)
        }
        
        // Auto advance
        if autoAdvance {
            advanceStep()
        }
    }
    
    /// Enter a chord (multiple notes at same beat position)
    func enterChord(pitches: [(pitch: UInt8, velocity: UInt8)]) {
        guard var region = targetRegion else { return }
        
        let gridStep = stepDuration.stepDurationBeats(timeSignature: timeSignature)
        for (pitch, vel) in pitches {
            let note = MIDINote(
                id: UUID(),
                pitch: pitch,
                velocity: vel,
                startBeat: stepPositionBeats,
                durationBeats: gridStep,
                channel: 0
            )
            region.addNote(note)
            
            // Preview the notes
            if previewNote {
                onNotePreview?(pitch, vel)
            }
        }
        
        targetRegion = region
        onRegionModified?(region)
        
        // Auto advance after chord
        if autoAdvance {
            advanceStep()
        }
    }
    
    /// Delete the last entered note
    func deleteLastNote() {
        guard var region = targetRegion else { return }
        
        // Find notes at the previous step beat position
        let prevPositionBeats = max(0, stepPositionBeats - stepDuration.stepDurationBeats(timeSignature: timeSignature))
        let notesAtPosition = region.notes.filter { 
            abs($0.startBeat - prevPositionBeats) < 0.001 
        }
        
        if let lastNote = notesAtPosition.last {
            region.removeNotes(withIds: [lastNote.id])
            targetRegion = region
            onRegionModified?(region)
            
            // Move back to that position
            stepPositionBeats = prevPositionBeats
        }
    }
    
    // MARK: - MIDI Callbacks
    
    private func setupMIDICallbacks() {
        // THREAD SAFETY: Use DispatchQueue.main.async instead of Task { @MainActor }
        // Task creation can crash in swift_getObjectType when accessing weak self
        midiDeviceManager?.onNoteOn = { [weak self] pitch, velocity, _ in
            DispatchQueue.main.async {
                self?.handleMIDINoteOn(pitch: pitch, velocity: velocity)
            }
        }
        
        midiDeviceManager?.onNoteOff = { [weak self] pitch, _ in
            DispatchQueue.main.async {
                self?.handleMIDINoteOff(pitch: pitch)
            }
        }
    }
    
    private func clearMIDICallbacks() {
        midiDeviceManager?.onNoteOn = nil
        midiDeviceManager?.onNoteOff = nil
    }
    
    private func handleMIDINoteOn(pitch: UInt8, velocity: UInt8) {
        guard isActive else { return }
        
        heldNotes.insert(pitch)
        pendingChordNotes.append((pitch: pitch, velocity: velocity))
        
        // Reset chord timer
        chordTimer?.invalidate()
        // THREAD SAFETY: Use DispatchQueue.main.async instead of Task { @MainActor }
        chordTimer = Timer.scheduledTimer(withTimeInterval: chordTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.commitPendingChord()
            }
        }
    }
    
    private func handleMIDINoteOff(pitch: UInt8) {
        guard isActive else { return }
        
        heldNotes.remove(pitch)
        onNoteOff?(pitch)
        
        // If all notes released and we have pending notes, commit immediately
        if heldNotes.isEmpty && !pendingChordNotes.isEmpty {
            chordTimer?.invalidate()
            commitPendingChord()
        }
    }
    
    private func commitPendingChord() {
        guard !pendingChordNotes.isEmpty else { return }
        
        if pendingChordNotes.count == 1 {
            let note = pendingChordNotes[0]
            enterNote(pitch: note.pitch, velocity: note.velocity)
        } else {
            enterChord(pitches: pendingChordNotes)
        }
        
        pendingChordNotes.removeAll()
    }
    
    // MARK: - Convenience Properties
    
    /// Get available step durations
    static var availableDurations: [SnapResolution] {
        [.bar, .half, .quarter, .eighth, .sixteenth, .thirtysecond, .tripletEighth, .tripletSixteenth]
    }
    
    /// Formatted beat position string (bar.beat.tick)
    var positionString: String {
        MIDIHelper.formatBeatPosition(stepPositionBeats)
    }
    
    /// Notes at current beat position
    var notesAtCurrentPosition: [MIDINote] {
        targetRegion?.notes.filter { 
            abs($0.startBeat - stepPositionBeats) < 0.001 
        } ?? []
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Prevents double-free from implicit Swift Concurrency property change notification tasks
    }
}

