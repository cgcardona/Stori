//
//  ScoreEntryController.swift
//  Stori
//
//  Step-time entry and editing controller for the Score view
//  Supports MIDI keyboard input, duration selection, and transformation tools
//

import SwiftUI
import Combine
import Observation

// MARK: - Score Entry Controller

/// Manages step-time note entry and editing operations
@Observable
class ScoreEntryController {
    
    // MARK: - Observable State (UI-visible)
    
    /// Current cursor position in beats
    var cursorPosition: Double = 0
    
    /// Currently selected note duration
    var currentDuration: NoteDuration = .quarter
    
    /// Whether step entry mode is active
    var isStepEntryActive: Bool = false
    
    /// Number of dots on the current duration
    var dotCount: Int = 0
    
    /// Whether the next note should be tied to the previous
    var isTieActive: Bool = false
    
    /// Current entry mode
    var entryMode: ScoreEntryMode = .select
    
    // MARK: - Configuration (internal, not observable)
    
    @ObservationIgnored private var tempo: Double = 120.0
    @ObservationIgnored private var midiRegion: MIDIRegion?
    @ObservationIgnored private var onRegionUpdate: ((MIDIRegion) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Deinit Protection (ASan Issue #84742+)
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Root cause: @Observable classes have implicit Swift Concurrency tasks
        // for property change notifications that can cause double-free on deinit.
        // See: MetronomeEngine, ProjectExportService, AutomationServer, LLMComposerClient,
        //      AudioAnalysisService, AudioExportService, SelectionManager, ScrollSyncModel,
        //      RegionDragState, AudioAnalyzer
        // https://github.com/cgcardona/Stori/issues/AudioEngine-MemoryBug
    }
    
    /// Configure with a MIDI region and update callback
    func configure(
        region: MIDIRegion,
        tempo: Double,
        onUpdate: @escaping (MIDIRegion) -> Void
    ) {
        self.midiRegion = region
        self.tempo = tempo
        self.onRegionUpdate = onUpdate
    }
    
    // MARK: - Duration Management
    
    /// Get the effective duration including dots
    var effectiveDuration: Double {
        var duration = currentDuration.rawValue
        var dotMultiplier = 0.5
        for _ in 0..<dotCount {
            duration += currentDuration.rawValue * dotMultiplier
            dotMultiplier *= 0.5
        }
        return duration
    }
    
    /// Set duration from keyboard shortcut (1-7)
    func setDurationFromKey(_ key: Int) {
        switch key {
        case 1: currentDuration = .whole
        case 2: currentDuration = .half
        case 3: currentDuration = .quarter
        case 4: currentDuration = .eighth
        case 5: currentDuration = .sixteenth
        case 6: currentDuration = .thirtySecond
        case 7: currentDuration = .sixtyFourth
        default: break
        }
    }
    
    /// Toggle dotted note
    func toggleDot() {
        dotCount = (dotCount + 1) % 3 // 0, 1, or 2 dots
    }
    
    /// Toggle tie
    func toggleTie() {
        isTieActive.toggle()
    }
    
    // MARK: - Step Entry
    
    /// Handle MIDI note input during step entry
    func handleMIDINoteOn(pitch: UInt8, velocity: UInt8) {
        guard isStepEntryActive, var region = midiRegion else { return }
        
        let startBeat = cursorPosition
        let durationBeats = effectiveDuration
        
        let newNote = MIDINote(
            pitch: pitch,
            velocity: velocity,
            startBeat: startBeat,
            durationBeats: durationBeats
        )
        
        region.notes.append(newNote)
        onRegionUpdate?(region)
        
        // Advance cursor
        cursorPosition += effectiveDuration
        
        // Reset tie after use
        if isTieActive {
            isTieActive = false
        }
        
    }
    
    /// Insert a rest at the cursor position
    func insertRest() {
        // Rests don't add notes, just advance the cursor
        cursorPosition += effectiveDuration
    }
    
    /// Move cursor backward
    func moveCursorBack() {
        cursorPosition = max(0, cursorPosition - effectiveDuration)
    }
    
    /// Move cursor forward
    func moveCursorForward() {
        cursorPosition += effectiveDuration
    }
    
    /// Jump cursor to a specific beat
    func setCursor(toBeat beat: Double) {
        cursorPosition = max(0, beat)
    }
    
    // MARK: - Transformation Operations
    
    /// Transpose selected notes by semitones
    func transpose(notes: [UUID], by semitones: Int, in region: inout MIDIRegion) {
        for i in 0..<region.notes.count {
            if notes.contains(region.notes[i].id) {
                let newPitch = Int(region.notes[i].pitch) + semitones
                region.notes[i].pitch = UInt8(max(0, min(127, newPitch)))
            }
        }
        onRegionUpdate?(region)
    }
    
    /// Transpose up one octave
    func transposeOctaveUp(notes: [UUID], in region: inout MIDIRegion) {
        transpose(notes: notes, by: 12, in: &region)
    }
    
    /// Transpose down one octave
    func transposeOctaveDown(notes: [UUID], in region: inout MIDIRegion) {
        transpose(notes: notes, by: -12, in: &region)
    }
    
    /// Double the duration of selected notes
    func doubleDuration(notes: [UUID], in region: inout MIDIRegion) {
        for i in 0..<region.notes.count {
            if notes.contains(region.notes[i].id) {
                region.notes[i].durationBeats *= 2
            }
        }
        onRegionUpdate?(region)
    }
    
    /// Halve the duration of selected notes
    func halveDuration(notes: [UUID], in region: inout MIDIRegion) {
        for i in 0..<region.notes.count {
            if notes.contains(region.notes[i].id) {
                region.notes[i].durationBeats /= 2
            }
        }
        onRegionUpdate?(region)
    }
    
    /// Invert selected notes around a pivot pitch
    func invert(notes: [UUID], aroundPitch pivot: UInt8, in region: inout MIDIRegion) {
        for i in 0..<region.notes.count {
            if notes.contains(region.notes[i].id) {
                let distance = Int(region.notes[i].pitch) - Int(pivot)
                let newPitch = Int(pivot) - distance
                region.notes[i].pitch = UInt8(max(0, min(127, newPitch)))
            }
        }
        onRegionUpdate?(region)
    }
    
    /// Reverse the order of selected notes (retrograde)
    func retrograde(notes: [UUID], in region: inout MIDIRegion) {
        let selectedIndices = region.notes.indices.filter { notes.contains(region.notes[$0].id) }
        guard selectedIndices.count > 1 else { return }
        
        let startBeats = selectedIndices.map { region.notes[$0].startBeat }
        let reversedStartBeats = startBeats.reversed()
        
        for (index, startBeat) in zip(selectedIndices, reversedStartBeats) {
            region.notes[index].startBeat = startBeat
        }
        
        onRegionUpdate?(region)
    }
    
    /// Quantize selected notes to a grid (resolution.rawValue is in beats)
    func quantize(notes: [UUID], to resolution: NoteDuration, in region: inout MIDIRegion) {
        let gridSizeBeats = resolution.rawValue
        
        for i in 0..<region.notes.count {
            if notes.contains(region.notes[i].id) {
                let quantizedStart = round(region.notes[i].startBeat / gridSizeBeats) * gridSizeBeats
                region.notes[i].startBeat = quantizedStart
            }
        }
        onRegionUpdate?(region)
    }
    
    // MARK: - Delete Operations
    
    /// Delete selected notes
    func deleteNotes(_ noteIds: Set<UUID>, from region: inout MIDIRegion) {
        region.notes.removeAll { noteIds.contains($0.id) }
        onRegionUpdate?(region)
    }
    
    // MARK: - Keyboard Shortcut Handler
    
    /// Handle keyboard input
    func handleKeyPress(_ key: String, modifiers: EventModifiers) -> Bool {
        switch key {
        case "1", "2", "3", "4", "5", "6", "7":
            if let num = Int(key) {
                setDurationFromKey(num)
                return true
            }
        case ".":
            toggleDot()
            return true
        case "t", "T":
            toggleTie()
            return true
        case "r", "R":
            insertRest()
            return true
        case " ": // Space
            // Toggle playback (handled by parent)
            return false
        default:
            break
        }
        return false
    }
}

// MARK: - Duration Palette View

/// Visual duration selector palette
struct DurationPaletteView: View {
    @Bindable var controller: ScoreEntryController
    
    private let durations: [(NoteDuration, String, String)] = [
        (.whole, "𝅝", "Whole"),
        (.half, "𝅗𝅥", "Half"),
        (.quarter, "♩", "Quarter"),
        (.eighth, "♪", "Eighth"),
        (.sixteenth, "𝅘𝅥𝅯", "16th"),
        (.thirtySecond, "𝅘𝅥𝅰", "32nd")
    ]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(durations, id: \.0) { duration, symbol, name in
                Button(action: {
                    controller.currentDuration = duration
                }) {
                    Text(symbol)
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .background(
                            controller.currentDuration == duration
                                ? Color.accentColor.opacity(0.3)
                                : Color.clear
                        )
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(name)
            }
            
            Divider().frame(height: 20)
            
            // Dot button
            Button(action: {
                controller.toggleDot()
            }) {
                Text(controller.dotCount > 0 ? "•\(controller.dotCount)" : "•")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(
                        controller.dotCount > 0
                            ? Color.orange.opacity(0.3)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Dotted note")
            
            // Tie button
            Button(action: {
                controller.toggleTie()
            }) {
                Image(systemName: "arrow.right.arrow.left")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(
                        controller.isTieActive
                            ? Color.purple.opacity(0.3)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Tie to next note")
        }
    }
}

// MARK: - Transform Menu View

/// Menu for transformation operations
struct TransformMenuView: View {
    let selectedNotes: Set<UUID>
    let onTranspose: (Int) -> Void
    let onDoubleDuration: () -> Void
    let onHalveDuration: () -> Void
    let onInvert: () -> Void
    let onRetrograde: () -> Void
    let onQuantize: (NoteDuration) -> Void
    
    var body: some View {
        Menu {
            Menu("Transpose") {
                Button("Up Octave (⌘↑)") { onTranspose(12) }
                Button("Down Octave (⌘↓)") { onTranspose(-12) }
                Divider()
                Button("Up Half Step") { onTranspose(1) }
                Button("Down Half Step") { onTranspose(-1) }
                Divider()
                Button("Up Whole Step") { onTranspose(2) }
                Button("Down Whole Step") { onTranspose(-2) }
            }
            .disabled(selectedNotes.isEmpty)
            
            Menu("Duration") {
                Button("Double Duration") { onDoubleDuration() }
                Button("Halve Duration") { onHalveDuration() }
            }
            .disabled(selectedNotes.isEmpty)
            
            Divider()
            
            Button("Invert") { onInvert() }
                .disabled(selectedNotes.isEmpty)
            
            Button("Retrograde") { onRetrograde() }
                .disabled(selectedNotes.isEmpty)
            
            Divider()
            
            Menu("Quantize") {
                Button("Quarter Notes") { onQuantize(.quarter) }
                Button("Eighth Notes") { onQuantize(.eighth) }
                Button("Sixteenth Notes") { onQuantize(.sixteenth) }
            }
            .disabled(selectedNotes.isEmpty)
            
        } label: {
            Label("Transform", systemImage: "wand.and.stars")
        }
    }
}

