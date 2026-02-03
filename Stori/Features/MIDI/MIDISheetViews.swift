//
//  MIDISheetViews.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Wrapper views for Piano Roll and Synthesizer sheets.
//

import SwiftUI
import Combine
import Observation

// MARK: - Piano Roll Sheet Wrapper

struct PianoRollSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// Access shared instrument manager for track info display
    private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    /// Dedicated preview sampler for the Piano Roll (always available)
    @State private var previewSampler = PianoRollPreviewSampler()
    
    /// For auto-releasing preview notes
    @State private var previewNoteTask: Task<Void, Never>?
    
    @State private var testRegion = MIDIRegion(
        name: "Demo MIDI Region",
        notes: [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1),
            MIDINote(pitch: 64, velocity: 80, startBeat: 1, durationBeats: 0.5),
            MIDINote(pitch: 67, velocity: 90, startBeat: 1.5, durationBeats: 1.5),
            MIDINote(pitch: 72, velocity: 100, startBeat: 3, durationBeats: 1),
            MIDINote(pitch: 65, velocity: 85, startBeat: 4, durationBeats: 0.75),
            MIDINote(pitch: 69, velocity: 95, startBeat: 5, durationBeats: 1.25),
            MIDINote(pitch: 60, velocity: 110, startBeat: 6.5, durationBeats: 1.5)
        ],
        durationBeats: 8.0
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            pianoRollHeader
            
            Divider()
            
            // Piano Roll with note preview through dedicated sampler
            PianoRollView(
                region: $testRegion,
                tempo: 120.0,  // [PHASE-3] Default tempo for test view
                cycleEnabled: false,  // [PHASE-4] No cycle in test view
                onPreviewNote: { pitch in
                    previewNote(pitch)
                },
                onStopPreview: {
                    // Test view doesn't need stop - notes auto-release
                }
            )
        }
        .frame(width: 1000, height: 600)
        .onAppear {
            previewSampler.start()
        }
        .onDisappear {
            previewSampler.stop()
        }
    }
    
    /// Preview a note using the dedicated acoustic piano sampler
    private func previewNote(_ pitch: UInt8) {
        previewNoteTask?.cancel()
        previewSampler.noteOn(pitch: pitch, velocity: 100)
        previewNoteTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms for piano decay
            if !Task.isCancelled {
                await MainActor.run {
                    previewSampler.noteOff(pitch: pitch)
                }
            }
        }
    }
    
    private var pianoRollHeader: some View {
        HStack {
            Image(systemName: "pianokeys.inverse")
                .font(.title2)
                .foregroundStyle(.linearGradient(
                    colors: [.green, .teal],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            
            Text("Piano Roll Editor")
                .font(.headline)
            
            // Track indicator
            if let trackName = instrumentManager.activeTrackName,
               let trackColor = instrumentManager.activeTrackColor {
                HStack(spacing: 6) {
                    Circle()
                        .fill(trackColor)
                        .frame(width: 10, height: 10)
                    Text("→ \(trackName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            } else {
                Text("Demo Mode")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.leading, 8)
            }
            
            Spacer()
            
            Text("\(testRegion.notes.count) notes")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Synthesizer Sheet Wrapper

struct SynthesizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// Access shared instrument manager for track routing
    private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    /// Fallback synth for when no track is selected
    @State private var fallbackSynth: SynthEngine?
    
    /// Current synth engine (from track or fallback)
    private var activeSynth: SynthEngine? {
        if let instrument = instrumentManager.activeInstrument,
           let synth = instrument.synthEngine {
            return synth
        }
        return fallbackSynth
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            synthHeader
            
            Divider()
            
            // Synthesizer View
            if let synth = activeSynth {
                SynthesizerView(engine: synth)
            } else {
                ProgressView("Loading Synthesizer...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 800, height: 700)
        .task {
            await setupFallbackSynth()
        }
        .onDisappear {
            fallbackSynth?.stop()
        }
    }
    
    private var synthHeader: some View {
        HStack {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.title2)
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            
            Text("Synthesizer")
                .font(.headline)
            
            // Track indicator
            if let trackName = instrumentManager.activeTrackName,
               let trackColor = instrumentManager.activeTrackColor {
                HStack(spacing: 6) {
                    Circle()
                        .fill(trackColor)
                        .frame(width: 10, height: 10)
                    Text("→ \(trackName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            }
            
            Spacer()
            
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    @MainActor
    private func setupFallbackSynth() async {
        let engine = SynthEngine()
        do {
            try engine.start()
            fallbackSynth = engine
        } catch {
        }
    }
}


// MARK: - Piano Roll Panel Content (for bottom panel)

struct PianoRollPanelContent: View {
    /// The MIDI region to edit (if any is selected)
    @Binding var midiRegion: MIDIRegion?
    
    /// Track ID the region belongs to (for saving edits)
    let trackId: UUID?
    
    /// Project manager for saving changes
    var projectManager: ProjectManager
    
    /// Audio engine for playhead position
    var audioEngine: AudioEngine
    
    /// Whether to show the internal header (set to false when using unified header in parent)
    var showHeader: Bool = true
    
    /// [PHASE-4] Snap to grid toggle state from parent
    var snapToGrid: Bool = true
    
    /// Access shared instrument manager for track info display
    private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    /// Dedicated preview sampler for the Piano Roll (always available)
    @State private var previewSampler = PianoRollPreviewSampler()
    
    /// Internal editable copy of the region
    @State private var editableRegion: MIDIRegion?
    
    /// Empty region used when no MIDI region is selected (shows blank piano roll)
    @State private var emptyRegion = MIDIRegion(
        name: "Empty Region",
        notes: [],  // No notes - shows blank piano roll
        durationBeats: 8.0
    )
    
    /// For auto-releasing preview notes
    @State private var previewNoteTask: Task<Void, Never>?
    
    /// Currently playing preview pitch (for proper note-off when switching)
    @State private var currentPreviewPitch: UInt8? = nil
    
    /// The region binding to use for PianoRollView
    private var regionBinding: Binding<MIDIRegion> {
        if editableRegion != nil {
            return Binding(
                get: { editableRegion ?? emptyRegion },
                set: { newValue in
                    editableRegion = newValue
                    // CRITICAL: Also update the parent binding so Score view gets updated data
                    midiRegion = newValue
                    // Save changes to project (including CC and pitch bend automation)
                    if let trackId = trackId {
                        projectManager.updateMIDIRegion(
                            newValue.id,
                            on: trackId,
                            notes: newValue.notes,
                            controllerEvents: newValue.controllerEvents,
                            pitchBendEvents: newValue.pitchBendEvents
                        )
                    }
                }
            )
        } else {
            // No region selected - show empty piano roll
            return $emptyRegion
        }
    }
    
    /// Whether we have a valid track instrument to use
    private var hasTrackInstrument: Bool {
        guard let trackId = trackId else { return false }
        return instrumentManager.getInstrument(for: trackId) != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Track routing header (optional - hide when parent provides unified header)
            if showHeader {
                trackRoutingHeader
                Divider()
            }
            
            // Piano Roll with note preview through track instrument or fallback sampler
            // [PHASE-4] Convert cycle times from seconds to beats
            let tempo = projectManager.currentProject?.tempo ?? 120.0
            let beatsPerSecond = tempo / 60.0
            let secondsPerBeat = 60.0 / tempo
            
            // PERF: Don't pass playheadPosition/isPlaying - PianoRoll reads AudioEngine directly
            // This prevents the parent view from re-rendering on every playhead update
            PianoRollView(
                region: regionBinding,
                tempo: tempo,  // [PHASE-3] Project tempo for measure display
                cycleEnabled: audioEngine.isCycleEnabled,  // [PHASE-4] Cycle region from audio engine
                cycleStartTime: audioEngine.cycleStartBeat,  // Already in beats!
                cycleEndTime: audioEngine.cycleEndBeat,      // Already in beats!
                snapToGrid: snapToGrid,  // [PHASE-4] Pass snap toggle state
                onCycleRegionChanged: { startBeats, endBeats in
                    // [PHASE-4] Update audio engine directly with beats
                    audioEngine.setCycleRegion(startBeat: startBeats, endBeat: endBeats)
                },
                onPreviewNote: { pitch in
                    previewNote(pitch)
                },
                onStopPreview: {
                    stopCurrentPreview()
                }
            )
        }
        .onAppear {
            // Always start fallback sampler (it will be used if no track instrument is available)
            previewSampler.start()
            
            syncRegionFromBinding()
        }
        .onChange(of: midiRegion) { _, newRegion in
            // Sync when parent binding changes (e.g., user selects different region)
            if let region = newRegion {
                if editableRegion?.id != region.id {
                    // Different region selected - reload
                    editableRegion = region
                }
                // If same region but notes differ (e.g., from project reload), update
                else if editableRegion?.notes.count != region.notes.count {
                    editableRegion = region
                }
            }
            
            // Log instrument status for debugging
            if let trackId = trackId {
                if let instrument = instrumentManager.getInstrument(for: trackId) {
                } else {
                }
            } else {
            }
        }
        .onDisappear {
            // Stop any playing preview note to prevent stuck notes
            if let pitch = currentPreviewPitch {
                stopPreviewNote(pitch)
            }
            previewNoteTask?.cancel()
            previewSampler.stop()
        }
    }
    
    /// Preview a note using the track's instrument (or fallback sampler in demo mode)
    private func previewNote(_ pitch: UInt8) {
        // Cancel any pending auto-release
        previewNoteTask?.cancel()
        
        // Stop the previous note immediately to prevent stuck notes
        if let previousPitch = currentPreviewPitch, previousPitch != pitch {
            stopPreviewNote(previousPitch)
        }
        
        currentPreviewPitch = pitch
        
        // Use track instrument if available, otherwise use fallback sampler
        if let trackId = trackId, let instrument = instrumentManager.getInstrument(for: trackId) {
            // Play through the track's actual instrument (synth or sampler)
            instrument.noteOn(pitch: pitch, velocity: 100)
            previewNoteTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                await MainActor.run {
                    stopPreviewNote(pitch)
                }
            }
        } else {
            // Demo mode: use fallback acoustic piano sampler
            previewSampler.noteOn(pitch: pitch, velocity: 100)
            previewNoteTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms for piano decay
                await MainActor.run {
                    stopPreviewNote(pitch)
                }
            }
        }
    }
    
    /// Stop a preview note (sends note-off to the appropriate instrument)
    private func stopPreviewNote(_ pitch: UInt8) {
        if let trackId = trackId, let instrument = instrumentManager.getInstrument(for: trackId) {
            instrument.noteOff(pitch: pitch)
        } else {
            previewSampler.noteOff(pitch: pitch)
        }
        
        // Clear current preview if this was it
        if currentPreviewPitch == pitch {
            currentPreviewPitch = nil
        }
    }
    
    /// Stop the currently playing preview note (called when drag ends)
    private func stopCurrentPreview() {
        previewNoteTask?.cancel()
        previewNoteTask = nil
        
        if let pitch = currentPreviewPitch {
            stopPreviewNote(pitch)
        }
    }
    
    /// Sync editableRegion from the midiRegion binding or auto-load from track
    private func syncRegionFromBinding() {
        if let region = midiRegion {
            // Explicit region passed - use it
            editableRegion = region
        } else if let trackId = trackId {
            // No explicit region, but we have a track - try to load its first MIDI region
            if let project = projectManager.currentProject,
               let track = project.tracks.first(where: { $0.id == trackId }),
               let firstRegion = track.midiRegions.first {
                editableRegion = firstRegion
            } else {
            }
        }
    }
    
    private var trackRoutingHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "pianokeys.inverse")
                .foregroundColor(.teal)
            
            if let region = editableRegion {
                // Editing a real region
                if let trackName = instrumentManager.activeTrackName,
                   let trackColor = instrumentManager.activeTrackColor {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(trackColor)
                            .frame(width: 10, height: 10)
                        Text("Editing: \(trackName)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(region.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if trackId != nil {
                // Track selected but no specific region
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Double-click a MIDI region on the timeline to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // No track selected
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Select a MIDI track to preview sounds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Notes count
            Text("\(regionBinding.wrappedValue.notes.count) notes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Synthesizer Panel Content (for bottom panel)

struct SynthesizerPanelContent: View {
    /// Access shared instrument manager for track routing
    private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    /// Fallback synth for when no track is selected
    @State private var fallbackSynth: SynthEngine?
    
    /// Current synth engine (from track or fallback)
    private var activeSynth: SynthEngine? {
        if let instrument = instrumentManager.activeInstrument,
           let synth = instrument.synthEngine {
            return synth
        }
        return fallbackSynth
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Track routing header
            trackRoutingHeader
            
            Divider()
            
            // Synthesizer content
            Group {
                if let synth = activeSynth {
                    ScrollView {
                        SynthesizerView(engine: synth)
                    }
                } else {
                    VStack {
                        ProgressView()
                        Text("Loading Synthesizer...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task {
            await setupFallbackSynth()
        }
        .onDisappear {
            // Only stop fallback synth - track instruments are managed by InstrumentManager
            fallbackSynth?.stop()
        }
    }
    
    private var trackRoutingHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .foregroundColor(.purple)
            
            if let trackName = instrumentManager.activeTrackName,
               let trackColor = instrumentManager.activeTrackColor {
                HStack(spacing: 6) {
                    Circle()
                        .fill(trackColor)
                        .frame(width: 10, height: 10)
                    Text("Editing: \(trackName)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Select a MIDI track to edit its synth, or use standalone mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Synth status
            if activeSynth != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    @MainActor
    private func setupFallbackSynth() async {
        let engine = SynthEngine()
        do {
            try engine.start()
            fallbackSynth = engine
        } catch {
        }
    }
}

// MARK: - Piano Roll Preview Sampler

/// Dedicated sampler for previewing notes in the Piano Roll.
/// Uses the SoundFont's Acoustic Grand Piano for a beautiful, consistent preview sound.
@Observable
@MainActor
class PianoRollPreviewSampler {
    @ObservationIgnored private var samplerEngine: SamplerEngine?
    @ObservationIgnored private var isRunning = false
    
    init() {}
    
    /// Start the preview sampler with acoustic piano
    func start() {
        guard !isRunning else { return }
        
        do {
            // Use factory method for preview sampler (isolated from main DAW engine)
            let engine = SamplerEngine.createPreviewSampler()
            try engine.start()
            
            // Load SoundFont with acoustic piano using the singleton
            if let sfURL = SoundFontManager.shared.anySoundFontURL() {
                try engine.loadSoundFont(at: sfURL)
            } else {
            }
            
            samplerEngine = engine
            isRunning = true
        } catch {
        }
    }
    
    /// Stop the preview sampler
    func stop() {
        samplerEngine?.allNotesOff()
        samplerEngine?.stop()
        samplerEngine = nil
        isRunning = false
    }
    
    /// Play a note
    func noteOn(pitch: UInt8, velocity: UInt8) {
        samplerEngine?.noteOn(pitch: pitch, velocity: velocity)
    }
    
    /// Stop a note
    func noteOff(pitch: UInt8) {
        samplerEngine?.noteOff(pitch: pitch)
    }
}