//
//  MainDAWView.swift
//  Stori
//
//  Main DAW interface combining timeline, mixer, and transport
//

import SwiftUI
import AVFoundation

enum MainTab: String, CaseIterable {
    case daw = "DAW"
    case marketplace = "Marketplace"
    case wallet = "Wallet"
    
    var title: String {
        return self.rawValue
    }
    
    var iconName: String {
        switch self {
        case .daw:
            return "waveform"
        case .marketplace:
            return "cart"
        case .wallet:
            return "wallet.bifold"
        }
    }
}

// MARK: - DAW Sheet Types

enum DAWSheet: String, Identifiable {
    case virtualKeyboard
    
    var id: String { rawValue }
}

/// Global state tracker for UI elements that need to be accessed from NSEvent handlers
/// NSEvent closures capture @State values at creation time, so we need a class-based workaround
final class DAWUIState {
    static let shared = DAWUIState()
    var isSynthesizerVisible: Bool = false      // Synthesizer panel at bottom
    var isVirtualKeyboardOpen: Bool = false      // Virtual keyboard sheet
    
    /// Returns true if any keyboard that should capture letter keys is visible
    var shouldCaptureMusicKeys: Bool {
        isSynthesizerVisible || isVirtualKeyboardOpen
    }
    
    private init() {}
}

struct MainDAWView: View {
    // SINGLETON: Use shared AudioEngine - a DAW must have exactly ONE audio engine.
    // Multiple windows can exist but they all share this single engine instance.
    private var audioEngine = SharedAudioEngine.shared
    @State private var metronomeEngine = MetronomeEngine()
    private var projectManager = SharedProjectManager.shared
    @State private var exportService = ProjectExportService()
    
    // MARK: - Automation Server (Agent Swarms)
    @State private var automationServer = AutomationServer()
    @State private var composerClient = LLMComposerClient()
    @State private var commandDispatcher: AICommandDispatcher?
    
    // MARK: - Transient UI State (dialogs, sheets - NOT persisted)
    @State private var showingNewProjectSheet = false
    @State private var showingProjectBrowser = false
    @State private var showingAboutWindow = false
    @State private var showingCreateTrackDialog = false
    @State private var showingRenameTrackDialog = false
    @State private var renameTrackText = ""
    @State private var activeSheet: DAWSheet?
    @State private var showingExportAlert = false
    @State private var showingExportSettings = false
    @State private var exportedFileURL: URL?
    
    // MARK: - Coming Soon Sheets (Marketplace & Wallet)
    @State private var showingMarketplaceSheet = false
    @State private var showingWalletSheet = false
    @State private var showingTokenInput = false
    
    // MARK: - Selection State (transient, not persisted)
    @State private var selectedTrackId: UUID?
    @State private var selectedTrackIds: Set<UUID> = []  // Multi-track selection
    @State private var lastSelectedTrackId: UUID?  // For shift-click range selection
    @State private var selectedRegionId: UUID?
    @State private var selectedMIDIRegion: MIDIRegion?  // Currently selected MIDI region for Piano Roll
    @State private var selectedMIDITrackId: UUID?       // Track the selected MIDI region belongs to
    @State private var selectedMainTab: MainTab = .daw
    
    // MARK: - UI State (Single Source of Truth: project.uiState)
    // These computed properties read/write directly to project.uiState
    // This enables: AI control, persistence, and clean architecture
    
    // Fallback state for when no project is open
    @State private var fallbackShowingInspector: Bool = false  // Composer panel hidden until service is available
    
    private var horizontalZoom: Double {
        projectManager.currentProject?.uiState.horizontalZoom ?? 0.8
    }
    
    private var verticalZoom: Double {
        projectManager.currentProject?.uiState.verticalZoom ?? 1.0
    }
    
    private var snapToGrid: Bool {
        projectManager.currentProject?.uiState.snapToGrid ?? true
    }
    
    private var timeDisplayMode: TimeDisplayMode {
        let mode = projectManager.currentProject?.uiState.timeDisplayMode ?? "beats"
        return mode == "beats" ? .beats : .time
    }
    
    private var showingInspector: Bool {
        projectManager.currentProject?.uiState.showingInspector ?? fallbackShowingInspector
    }
    
    private var showingMixer: Bool {
        projectManager.currentProject?.uiState.showingMixer ?? false
    }
    
    private var showingStepSequencer: Bool {
        projectManager.currentProject?.uiState.showingStepSequencer ?? false
    }
    
    private var showingPianoRoll: Bool {
        projectManager.currentProject?.uiState.showingPianoRoll ?? false
    }
    
    private var showingSynthesizer: Bool {
        projectManager.currentProject?.uiState.showingSynthesizer ?? false
    }
    
    private var showingSelection: Bool {
        projectManager.currentProject?.uiState.showingSelection ?? false
    }
    
    private var catchPlayheadEnabled: Bool {
        projectManager.currentProject?.uiState.catchPlayheadEnabled ?? true
    }
    
    private var selectedEditorMode: MIDIEditorMode {
        let mode = projectManager.currentProject?.uiState.selectedEditorMode ?? "pianoRoll"
        return mode == "pianoRoll" ? .pianoRoll : .score
    }
    
    private var inspectorWidth: CGFloat {
        CGFloat(projectManager.currentProject?.uiState.inspectorWidth ?? 300)
    }
    
    private var mixerHeight: CGFloat {
        CGFloat(projectManager.currentProject?.uiState.mixerHeight ?? 600)
    }
    
    private var stepSequencerHeight: CGFloat {
        CGFloat(projectManager.currentProject?.uiState.stepSequencerHeight ?? 600)
    }
    
    private var pianoRollHeight: CGFloat {
        CGFloat(projectManager.currentProject?.uiState.pianoRollHeight ?? 600)
    }
    
    private var synthesizerHeight: CGFloat {
        CGFloat(projectManager.currentProject?.uiState.synthesizerHeight ?? 500)
    }
    
    // MARK: - UI State Setters (update project.uiState)
    
    private func setHorizontalZoom(_ value: Double) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.horizontalZoom = value
        projectManager.currentProject = project
    }
    
    private func setVerticalZoom(_ value: Double) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.verticalZoom = value
        projectManager.currentProject = project
    }
    
    private func setSnapToGrid(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.snapToGrid = value
        projectManager.currentProject = project
    }
    
    private func setTimeDisplayMode(_ value: TimeDisplayMode) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.timeDisplayMode = value == .beats ? "beats" : "time"
        projectManager.currentProject = project
    }
    
    private func setShowingInspector(_ value: Bool) {
        if var project = projectManager.currentProject {
            // Save to project state if project is open
            project.uiState.showingInspector = value
            projectManager.currentProject = project
        } else {
            // Use fallback state when no project is open
            fallbackShowingInspector = value
        }
    }
    
    private func setShowingMixer(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.showingMixer = value
        projectManager.currentProject = project
    }
    
    private func setShowingStepSequencer(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.showingStepSequencer = value
        projectManager.currentProject = project
    }
    
    private func setShowingPianoRoll(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.showingPianoRoll = value
        projectManager.currentProject = project
    }
    
    private func setShowingSynthesizer(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.showingSynthesizer = value
        projectManager.currentProject = project
        DAWUIState.shared.isSynthesizerVisible = value
    }
    
    private func setShowingSelection(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.showingSelection = value
        projectManager.currentProject = project
    }
    
    private func setCatchPlayheadEnabled(_ value: Bool) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.catchPlayheadEnabled = value
        projectManager.currentProject = project
    }
    
    private func setSelectedEditorMode(_ value: MIDIEditorMode) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.selectedEditorMode = value == .pianoRoll ? "pianoRoll" : "score"
        projectManager.currentProject = project
    }
    
    private func setInspectorWidth(_ value: CGFloat) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.inspectorWidth = Double(value)
        projectManager.currentProject = project
    }
    
    private func setMixerHeight(_ value: CGFloat) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.mixerHeight = Double(value)
        projectManager.currentProject = project
    }
    
    private func setStepSequencerHeight(_ value: CGFloat) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.stepSequencerHeight = Double(value)
        projectManager.currentProject = project
    }
    
    private func setPianoRollHeight(_ value: CGFloat) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.pianoRollHeight = Double(value)
        projectManager.currentProject = project
    }
    
    private func setSynthesizerHeight(_ value: CGFloat) {
        guard var project = projectManager.currentProject else { return }
        project.uiState.synthesizerHeight = Double(value)
        projectManager.currentProject = project
    }
    
    // MARK: - UI State Bindings (for SwiftUI controls)
    
    private var horizontalZoomBinding: Binding<Double> {
        Binding(
            get: { horizontalZoom },
            set: { setHorizontalZoom($0) }
        )
    }
    
    private var verticalZoomBinding: Binding<Double> {
        Binding(
            get: { verticalZoom },
            set: { setVerticalZoom($0) }
        )
    }
    
    private var snapToGridBinding: Binding<Bool> {
        Binding(
            get: { snapToGrid },
            set: { setSnapToGrid($0) }
        )
    }
    
    private var timeDisplayModeBinding: Binding<TimeDisplayMode> {
        Binding(
            get: { timeDisplayMode },
            set: { setTimeDisplayMode($0) }
        )
    }
    
    private var showingInspectorBinding: Binding<Bool> {
        Binding(
            get: { showingInspector },
            set: { setShowingInspector($0) }
        )
    }
    
    private var showingMixerBinding: Binding<Bool> {
        Binding(
            get: { showingMixer },
            set: { setShowingMixer($0) }
        )
    }
    
    private var showingStepSequencerBinding: Binding<Bool> {
        Binding(
            get: { showingStepSequencer },
            set: { setShowingStepSequencer($0) }
        )
    }
    
    private var showingPianoRollBinding: Binding<Bool> {
        Binding(
            get: { showingPianoRoll },
            set: { setShowingPianoRoll($0) }
        )
    }
    
    private var showingSynthesizerBinding: Binding<Bool> {
        Binding(
            get: { showingSynthesizer },
            set: { setShowingSynthesizer($0) }
        )
    }
    
    private var showingSelectionBinding: Binding<Bool> {
        Binding(
            get: { showingSelection },
            set: { setShowingSelection($0) }
        )
    }
    
    private var catchPlayheadEnabledBinding: Binding<Bool> {
        Binding(
            get: { catchPlayheadEnabled },
            set: { setCatchPlayheadEnabled($0) }
        )
    }
    
    private var selectedEditorModeBinding: Binding<MIDIEditorMode> {
        Binding(
            get: { selectedEditorMode },
            set: { setSelectedEditorMode($0) }
        )
    }
    
    // MARK: - Track Management
    private func showCreateTrackDialog() {
        showingCreateTrackDialog = true
    }
    
    private func createTracks(config: NewTrackConfig) async {
        var lastCreatedTrackId: UUID?
        
        for _ in 0..<config.count {
            switch config.type {
            case .midi:
                if let track = addMIDITrack() {
                    lastCreatedTrackId = track.id
                    // Instruments are selected via mixer channel strip's instrument slot
                    
                    // Apply output bus routing if selected
                    if let busId = config.outputBusId {
                        // TODO: Implement track output routing to bus
                    }
                }
            case .audio:
                if let track = addTrack() {
                    lastCreatedTrackId = track.id
                    
                    // Apply output bus routing if selected
                    if let busId = config.outputBusId {
                        // TODO: Implement track output routing to bus
                    }
                }
            }
        }
        
        // Select the last created track
        if let trackId = lastCreatedTrackId {
            selectedTrackId = trackId
            selectedTrackIds = [trackId]
            lastSelectedTrackId = trackId
        }
    }
    
    @discardableResult
    private func addTrack(name: String? = nil) -> AudioTrack? {
        // Let ProjectManager handle track naming logic (it finds highest number to avoid duplicates)
        let track = projectManager.addTrack(name: name)
        
        // Select the new audio track (matching MIDI track behavior)
        if let track = track {
            selectedTrackId = track.id
            selectedTrackIds = [track.id]  // Clear multi-selection and select only new track
            lastSelectedTrackId = track.id
        }
        
        return track
    }
    
    @discardableResult
    private func addMIDITrack(name: String? = nil) -> AudioTrack? {
        let midiTrackCount = projectManager.currentProject?.tracks.filter { $0.isMIDITrack }.count ?? 0
        let trackName = name ?? "MIDI Track \(midiTrackCount + 1)"
        
        // Add MIDI track to project manager
        let track = projectManager.addMIDITrack(name: trackName)
        
        // Select the new track and create its instrument
        if let track = track {
            selectedTrackId = track.id
            selectedTrackIds = [track.id]  // Clear multi-selection and select only new track
            lastSelectedTrackId = track.id
            InstrumentManager.shared.selectedTrackId = track.id
        }
        
        return track
    }
    
    /// Open Piano Roll for editing a specific MIDI region
    private func openPianoRollForRegion(_ region: MIDIRegion, on track: AudioTrack) {
        selectedMIDIRegion = region
        selectedMIDITrackId = track.id
        selectedTrackId = track.id
        setShowingPianoRoll(true)
    }
    
    // MARK: - Bottom Panel Management (Mutually Exclusive)
    
    /// Toggle mixer - closes other bottom panels if opening
    private func toggleMixer() {
        if showingMixer {
            setShowingMixer(false)
        } else {
            // Close all other bottom panels
            setShowingStepSequencer(false)
            setShowingPianoRoll(false)
            setShowingSynthesizer(false)
            setShowingMixer(true)
        }
    }
    
    /// Toggle step sequencer - closes other bottom panels if opening
    private func toggleStepSequencer() {
        if showingStepSequencer {
            setShowingStepSequencer(false)
        } else {
            // Close all other bottom panels
            setShowingMixer(false)
            setShowingPianoRoll(false)
            setShowingSynthesizer(false)
            setShowingStepSequencer(true)
        }
    }
    
    /// Toggle piano roll - closes other bottom panels if opening
    private func togglePianoRoll() {
        if showingPianoRoll {
            setShowingPianoRoll(false)
        } else {
            // Close all other bottom panels
            setShowingMixer(false)
            setShowingStepSequencer(false)
            setShowingSynthesizer(false)
            setShowingPianoRoll(true)
        }
    }
    
    /// Toggle synthesizer - closes other bottom panels if opening
    private func toggleSynthesizer() {
        if showingSynthesizer {
            setShowingSynthesizer(false)
        } else {
            // Close all other bottom panels
            setShowingMixer(false)
            setShowingStepSequencer(false)
            setShowingPianoRoll(false)
            setShowingSynthesizer(true)
        }
    }
    
    /// Toggle selection panel (left sidebar)
    private func toggleSelection() {
        setShowingSelection(!showingSelection)
    }
    
    // MARK: - Multi-Track Selection
    
    private func selectTrack(_ trackId: UUID, modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            // Command-click: Toggle selection
            if selectedTrackIds.contains(trackId) {
                selectedTrackIds.remove(trackId)
                // If we removed the primary selection, pick another
                if selectedTrackId == trackId {
                    selectedTrackId = selectedTrackIds.first
                }
            } else {
                selectedTrackIds.insert(trackId)
                selectedTrackId = trackId
                lastSelectedTrackId = trackId
            }
        } else if modifiers.contains(.shift), let lastId = lastSelectedTrackId,
                  let tracks = projectManager.currentProject?.tracks,
                  let lastIndex = tracks.firstIndex(where: { $0.id == lastId }),
                  let currentIndex = tracks.firstIndex(where: { $0.id == trackId }) {
            // Shift-click: Range selection
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            selectedTrackIds = Set(tracks[range].map { $0.id })
            selectedTrackId = trackId
        } else {
            // Plain click: Select only this track
            selectedTrackIds = [trackId]
            selectedTrackId = trackId
            lastSelectedTrackId = trackId
        }
    }
    
    private func deleteSelectedTracks() {
        guard let project = projectManager.currentProject else { return }
        
        guard !selectedTrackIds.isEmpty else {
            // Fall back to single track deletion if no multi-selection
            if let trackId = selectedTrackId,
               let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
                let track = project.tracks[trackIndex]
                // Register undo action BEFORE deleting
                UndoService.shared.registerDeleteTrack(track, at: trackIndex, projectManager: projectManager, audioEngine: audioEngine)
                projectManager.removeTrack(trackId)
                selectedTrackId = nil
            }
            return
        }
        
        // Register undo for multiple tracks (as a group)
        UndoService.shared.beginGroup(named: selectedTrackIds.count == 1 ? "Delete Track" : "Delete \(selectedTrackIds.count) Tracks")
        
        for trackId in selectedTrackIds {
            if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
                let track = project.tracks[trackIndex]
                UndoService.shared.registerDeleteTrack(track, at: trackIndex, projectManager: projectManager, audioEngine: audioEngine)
                projectManager.removeTrack(trackId)
            }
        }
        
        UndoService.shared.endGroup()
        
        // Clear selection after deletion
        selectedTrackIds.removeAll()
        selectedTrackId = nil
        lastSelectedTrackId = nil
    }
    
    private func renameSelectedTrack(to newName: String) {
        guard let trackId = selectedTrackId,
              var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].name = newName
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        renameTrackText = newName
        showingRenameTrackDialog = true
    }
    
    private func performRenameTrack() {
        guard let trackId = selectedTrackId,
              var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        // Rename the track
        project.tracks[trackIndex].name = renameTrackText
        
        // Also rename all MIDI regions on this track to match
        for i in 0..<project.tracks[trackIndex].midiRegions.count {
            project.tracks[trackIndex].midiRegions[i].name = renameTrackText
        }
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        showingRenameTrackDialog = false
    }
    
    /// Bounce a MIDI region to audio (creates new audio track - non-destructive)
    private func bounceMIDIRegionToAudio(_ region: MIDIRegion, on track: AudioTrack) {
        guard let project = projectManager.currentProject else { return }
        let projectTempo = project.tempo
        
        // Get the instrument for this track
        guard let instrument = InstrumentManager.shared.getOrCreateInstrument(for: track.id) else {
            return
        }
        
        // Perform bounce in background
        Task {
            do {
                let bounceEngine = MIDIBounceEngine()
                let audioURL = try await bounceEngine.bounce(
                    region: region,
                    instrument: instrument,
                    sampleRate: project.sampleRate,
                    tailDuration: 2.0
                )
                
                // Get file attributes
                let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let totalDuration = region.duration + 2.0
                
                // Create AudioFile from bounced file
                let audioFile = AudioFile(
                    name: "\(region.name) (Bounced)",
                    url: audioURL,
                    duration: totalDuration,
                    sampleRate: project.sampleRate,
                    channels: 2,
                    bitDepth: 32,
                    fileSize: fileSize,
                    format: .wav
                )
                
                // Create audio region
                // MIDIRegion.startTime is already in beats, use it directly
                let audioRegion = AudioRegion(
                    audioFile: audioFile,
                    startBeat: region.startTime,
                    durationBeats: region.duration,
                    tempo: projectTempo
                )
                
                // Create new audio track for the bounce (non-destructive workflow)
                await MainActor.run {
                    // Create new audio track with similar name
                    let bounceTrackName = "\(track.name) - Bounce"
                    
                    // Find the index of the source MIDI track to insert below it
                    let sourceTrackIndex = projectManager.currentProject?.tracks.firstIndex(where: { $0.id == track.id })
                    
                    // Add new audio track with same color as source
                    guard let newTrack = projectManager.addAudioTrack(
                        name: bounceTrackName,
                        color: track.color
                    ) else {
                        return
                    }
                    
                    // Add the audio region to the new track
                    projectManager.addRegionToTrack(audioRegion, trackId: newTrack.id)
                    
                    // Reorder to place below source MIDI track
                    if let sourceIndex = sourceTrackIndex,
                       let project = projectManager.currentProject {
                        projectManager.moveTrack(from: project.tracks.count - 1, to: sourceIndex + 1)
                    }
                    
                }
            } catch {
            }
        }
    }
    
    /// Delete a MIDI region from a track
    private func deleteMIDIRegion(_ region: MIDIRegion, from track: AudioTrack) {
        projectManager.removeMIDIRegion(region.id, from: track.id, audioEngine: audioEngine)
    }
    
    private func deleteSelectedTrack() {
        deleteSelectedTracks()
    }
    
    /// Delete the currently selected region (audio or MIDI)
    private func handleDeleteSelectedRegion() {
        guard let regionId = selectedRegionId else {
            return
        }
        
        // Find which track contains this region
        guard let project = projectManager.currentProject else { return }
        
        for track in project.tracks {
            // Check audio regions
            if track.regions.contains(where: { $0.id == regionId }) {
                projectManager.removeRegionFromTrack(regionId, trackId: track.id, audioEngine: audioEngine)
                selectedRegionId = nil
                // audioEngine.loadProject is now called inside removeRegionFromTrack
                return
            }
            
            // Check MIDI regions
            if track.midiRegions.contains(where: { $0.id == regionId }) {
                projectManager.removeMIDIRegion(regionId, from: track.id, audioEngine: audioEngine)
                selectedRegionId = nil
                selectedMIDIRegion = nil
                selectedMIDITrackId = nil
                setShowingPianoRoll(false)
                // audioEngine.loadProject is now called inside removeMIDIRegion
                return
            }
        }
        
    }
    
    /// Get the voice preset name of the currently selected track (if it's a MIDI track)
    private var selectedTrackVoicePreset: String? {
        guard let trackId = selectedTrackId,
              let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }),
              track.isMIDITrack else {
            return nil
        }
        return track.voicePreset
    }
    
    private func handleInstrumentSelection(_ instrumentName: String) {
        guard let trackId = selectedTrackId,
              var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              project.tracks[trackIndex].isMIDITrack else {
            return
        }
        
        // Update track's voice preset
        project.tracks[trackIndex].voicePreset = instrumentName
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Check if this is a synth preset or a GM instrument (SoundFont)
        if let synthPreset = SynthPreset.preset(named: instrumentName) {
            // It's a synth preset
            handleSynthPresetSelection(trackId: trackId, preset: synthPreset, trackName: project.tracks[trackIndex].name)
        } else if let gmInstrument = GMInstrument.allCases.first(where: { $0.name == instrumentName }) {
            // It's a GM instrument (SoundFont sampler)
            handleGMInstrumentSelection(trackId: trackId, instrument: gmInstrument, trackName: project.tracks[trackIndex].name)
        } else {
        }
    }
    
    private func handleSynthPresetSelection(trackId: UUID, preset: SynthPreset, trackName: String) {
        // Update track's voice preset so Library UI shows selection
        if var project = projectManager.currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].voicePreset = preset.name
            projectManager.currentProject = project
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
        
        // Get or create instrument (ensure it's a synth)
        if let instrument = InstrumentManager.shared.getOrCreateInstrument(for: trackId) {
            // Change to synth type if needed
            if instrument.type != .synth {
                instrument.changeType(to: .synth)
            }
            
            instrument.loadPreset(preset)
            
            // Start the instrument if not already running
            do {
                try instrument.start()
            } catch {
            }
        }
    }
    
    private func handleGMInstrumentSelection(trackId: UUID, instrument gmInstrument: GMInstrument, trackName: String) {
        // Update track's voice preset so Library UI shows selection
        if var project = projectManager.currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].voicePreset = gmInstrument.name
            projectManager.currentProject = project
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
        
        // Get or create instrument (ensure it's a sampler)
        if let trackInstrument = InstrumentManager.shared.getOrCreateInstrument(for: trackId) {
            // Change to sampler type if needed
            if trackInstrument.type != .sampler {
                trackInstrument.changeType(to: .sampler)
                
                // Load the SoundFont
                if let soundFontURL = SoundFontManager.shared.anySoundFontURL() {
                    do {
                        try trackInstrument.samplerEngine?.loadSoundFont(at: soundFontURL)
                    } catch {
                        return
                    }
                } else {
                    return
                }
            }
            
            // Load the specific GM instrument
            trackInstrument.loadGMInstrument(gmInstrument)
            
            // Start the instrument if not already running
            do {
                try trackInstrument.start()
            } catch {
                // Failed to start instrument
            }
        }
    }
    
    private func handleImportMIDIFile() {
        guard let selectedId = selectedTrackId,
              let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == selectedId }) else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "No Track Selected"
                alert.informativeText = "Please select a MIDI track before importing MIDI files."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Validate that selected track is a MIDI track (not audio)
        guard track.isMIDITrack else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Invalid Track Type"
                alert.informativeText = "MIDI files can only be imported to MIDI tracks. Audio tracks are for audio data only.\n\nPlease select a MIDI track or create a new one with File > New MIDI Track (⌘⇧M)."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Open file picker for .mid files
        let panel = NSOpenPanel()
        panel.title = "Import MIDI File"
        panel.message = "Select a MIDI file to import"
        panel.allowedContentTypes = [.midi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        let trackIdToUse = selectedId
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            
            self.processMIDIImport(url: url, toTrack: trackIdToUse)
        }
    }
    
    private func processMIDIImport(url: URL, toTrack trackId: UUID) {
        let result = MIDIImporter.importMIDIFile(from: url)
        
        switch result {
        case .success(let tracks):
            
            // Filter tracks with notes
            let tracksWithNotes = tracks.filter { !$0.notes.isEmpty }
            
            guard !tracksWithNotes.isEmpty else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Empty MIDI File"
                    alert.informativeText = "The selected MIDI file contains no notes."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
            
            // Multi-track MIDI files: Ask user if they want all tracks or just one
            if tracksWithNotes.count > 1 {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Multi-Track MIDI File Detected"
                    alert.informativeText = "This MIDI file contains \(tracksWithNotes.count) tracks with notes.\n\nWould you like to import all tracks (each as a separate track) or just the first track?"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Import All Tracks")
                    alert.addButton(withTitle: "Import First Track Only")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    
                    switch response {
                    case .alertFirstButtonReturn: // Import All
                        self.importAllMIDITracks(tracksWithNotes, toInitialTrack: trackId)
                    case .alertSecondButtonReturn: // Import First Only
                        self.importSingleMIDITrack(tracksWithNotes[0], toTrack: trackId)
                    default: // Cancel
                        break
                    }
                }
            } else {
                // Single track - import directly
                importSingleMIDITrack(tracksWithNotes[0], toTrack: trackId)
            }
            
        case .failure(let error):
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "MIDI Import Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    /// Import a single MIDI track
    private func importSingleMIDITrack(_ midiTrack: MIDITrackData, toTrack trackId: UUID) {
        // Get the DAW track name for the region
        let trackName: String
        if let project = projectManager.currentProject,
           let track = project.tracks.first(where: { $0.id == trackId }) {
            trackName = track.name
        } else {
            trackName = midiTrack.name
        }
        
        // Create MIDI region
        let region = MIDIRegion(
            name: trackName,
            notes: midiTrack.notes,
            duration: midiTrack.notes.map { $0.endTime }.max() ?? 4.0,
            contentLength: midiTrack.notes.map { $0.endTime }.max() ?? 4.0
        )
        
        #if DEBUG
        print("🎹 [MIDI Import] Created region '\(trackName)':")
        print("   - Note count: \(midiTrack.notes.count)")
        print("   - Duration: \(region.duration) beats")
        print("   - GM Program: \(midiTrack.gmProgram.map { String($0) } ?? "none")")
        print("   - First 5 notes: \(midiTrack.notes.prefix(5).map { "pitch=\($0.pitch) start=\($0.startTime) dur=\($0.duration)" })")
        #endif
        
        // Add to project
        projectManager.addMIDIRegion(region, to: trackId)
        
        // Assign instrument from MIDI file's program change, or default to piano
        if SoundFontManager.shared.hasSoundFont {
            let programToAssign = midiTrack.gmProgram ?? 0  // Default to Acoustic Grand Piano (0)
            assignGMInstrumentToTrack(trackId, programNumber: programToAssign)
        } else {
            // SoundFont not available - show warning
            showMissingSoundFontWarning()
        }
    }
    
    /// Import all MIDI tracks as separate DAW tracks
    private func importAllMIDITracks(_ midiTracks: [MIDITrackData], toInitialTrack initialTrackId: UUID) {
        guard projectManager.currentProject != nil else { return }
        
        // Use first track for the initially selected track
        if let firstTrack = midiTracks.first {
            importSingleMIDITrack(firstTrack, toTrack: initialTrackId)
        }
        
        // Create new tracks for remaining MIDI tracks
        for (index, midiTrack) in midiTracks.dropFirst().enumerated() {
            // Create new MIDI track
            guard let newTrack = addMIDITrack(name: midiTrack.name.isEmpty ? "MIDI Track \(index + 2)" : midiTrack.name) else {
                continue
            }
            
            // Create MIDI region
            let region = MIDIRegion(
                name: midiTrack.name.isEmpty ? newTrack.name : midiTrack.name,
                notes: midiTrack.notes,
                duration: midiTrack.notes.map { $0.endTime }.max() ?? 4.0
            )
            
            #if DEBUG
            print("🎹 [MIDI Import] Track \(index + 2) '\(midiTrack.name)': \(midiTrack.notes.count) notes, GM Program: \(midiTrack.gmProgram.map { String($0) } ?? "none")")
            #endif
            
            // Add region to new track
            projectManager.addMIDIRegion(region, to: newTrack.id)
            
            // Assign instrument from MIDI file's program change, or default to piano
            if SoundFontManager.shared.hasSoundFont {
                let programToAssign = midiTrack.gmProgram ?? 0  // Default to Acoustic Grand Piano (0)
                assignGMInstrumentToTrack(newTrack.id, programNumber: programToAssign)
            } else if index == 0 {
                // Only show warning once (for first track), not for every track
                showMissingSoundFontWarning()
            }
        }
        
        // Select the first track
        selectedTrackId = initialTrackId
        selectedTrackIds = [initialTrackId]
    }
    
    /// Assign a GM instrument to a track by program number (0-127)
    private func assignGMInstrumentToTrack(_ trackId: UUID, programNumber: Int) {
        guard let gmInstrument = GMInstrument(rawValue: programNumber) else {
            #if DEBUG
            print("🔴 [MIDI Import] Unknown GM program number: \(programNumber), defaulting to piano")
            #endif
            // Fall back to Acoustic Grand Piano if program number is invalid
            assignGMInstrumentToTrack(trackId, programNumber: 0)
            return
        }
        
        #if DEBUG
        print("🎹 [MIDI Import] Assigning \(gmInstrument.name) (GM \(programNumber)) to track")
        #endif
        
        // Use the proper audio engine flow (same as ProfessionalChannelStrip)
        Task { @MainActor in
            do {
                // Load through audio engine (proper way to initialize samplers)
                try await audioEngine.loadTrackGMInstrument(trackId: trackId, instrument: gmInstrument)
                
                // Update project model with instrument
                guard var project = projectManager.currentProject,
                      let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
                    return
                }
                
                project.tracks[trackIndex].gmProgram = gmInstrument.rawValue
                project.tracks[trackIndex].voicePreset = gmInstrument.name
                project.tracks[trackIndex].drumKitId = nil
                project.tracks[trackIndex].synthPresetId = nil
                project.modifiedAt = Date()
                projectManager.currentProject = project
                projectManager.hasUnsavedChanges = true
                
            } catch {
                #if DEBUG
                print("🔴 [MIDI Import] Failed to assign instrument: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// Assign a default GM instrument to a track by name (legacy helper)
    private func assignDefaultInstrumentToTrack(_ trackId: UUID, instrumentName: String) {
        guard let gmInstrument = GMInstrument.allCases.first(where: { $0.name == instrumentName }) else {
            return
        }
        assignGMInstrumentToTrack(trackId, programNumber: gmInstrument.rawValue)
    }
    
    /// Show warning when MIDI import requires SoundFont but it's not installed
    private func showMissingSoundFontWarning() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Instruments Required"
            alert.informativeText = """
            This MIDI file uses General MIDI instruments, but no SoundFont is installed.
            
            To hear sound, you need to:
            1. Open the Mixer panel
            2. Click the instrument selector for any track
            3. Go to the "SoundFont" tab
            4. Download the MuseScore General SoundFont (128 instruments)
            
            Without instruments, the MIDI notes will import but play silently.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Mixer")
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                // User clicked "Open Mixer"
                NotificationCenter.default.post(name: .toggleMixer, object: nil)
            }
        }
    }
    
    private func importAudioToSelectedTrack() {
        guard let selectedId = selectedTrackId,
              let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == selectedId }) else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "No Track Selected"
                alert.informativeText = "Please select an audio track before importing audio files."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Validate that selected track is an audio track (not MIDI)
        guard !track.isMIDITrack else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Invalid Track Type"
                alert.informativeText = "Audio files can only be imported to audio tracks. MIDI tracks are for MIDI data only.\n\nPlease select an audio track or create a new one with File > New Audio Track (⌘⇧N)."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Open file picker for .wav files
        let panel = NSOpenPanel()
        panel.title = "Import Audio File"
        panel.message = "Select a .wav audio file to import"
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            
            
            // Calculate first available position on selected track
            guard let track = project.tracks.first(where: { $0.id == selectedId }) else {
                return
            }
            let firstAvailablePosition = self.calculateFirstAvailablePosition(for: track)
            
            
            // Import the audio file (position in beats)
            self.importAudioFile(url: url, toTrack: selectedId, atBeat: firstAvailablePosition)
        }
    }
    
    /// Calculate first available position in BEATS for adding new content
    private func calculateFirstAvailablePosition(for track: AudioTrack) -> Double {
        // If no regions, start at 0
        guard !track.regions.isEmpty else {
            return 0.0
        }
        
        // Find the maximum end beat across all regions
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        let maxEndBeat = track.regions.map { $0.endBeat }.max() ?? 0.0
        
        return maxEndBeat
    }
    
    private func importAudioFile(url: URL, toTrack trackId: UUID, atBeat startBeat: Double) {
        do {
            // Enforce size limit before opening (prevents memory exhaustion)
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            guard fileSize <= AudioEngine.maxAudioImportFileSize else {
                return // File too large; could show alert
            }
            // Read audio file metadata
            let audioFile = try AVAudioFile(forReading: url)
            let durationSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let sampleRate = audioFile.fileFormat.sampleRate
            let channels = Int(audioFile.fileFormat.channelCount)

            // Create AudioFile model
            let audioFileModel = AudioFile(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                duration: durationSeconds,
                sampleRate: sampleRate,
                channels: channels,
                fileSize: fileSize,
                format: .wav
            )
            
            // Create AudioRegion (position in beats, duration in beats)
            let durationBeats = durationSeconds * (projectManager.currentProject?.tempo ?? 120.0) / 60.0
            let region = AudioRegion(
                audioFile: audioFileModel,
                startBeat: startBeat,
                durationBeats: durationBeats,
                tempo: projectManager.currentProject?.tempo ?? 120.0,
                isLooped: false,
                offset: 0.0
            )
            
            // 📊 COMPREHENSIVE LOGGING: Region creation from file import
            
            // Add region to track
            projectManager.addRegionToTrack(region, trackId: trackId)
            
            
        } catch {
        }
    }
    
    private func handleProjectRename(to newName: String) {
        do {
            try projectManager.renameCurrentProject(to: newName)
        } catch {
            // Handle rename errors
            // In a production app, you might want to show an alert to the user
        }
    }
    
    // MARK: - View Components
    
    private var bodyContent: some View {
        GeometryReader { geometry in
            dawContentView(geometry: geometry)
        }
    }
    
    var body: some View {
        bodyContent
            .modifier(DAWSheetModifiers(
                showingNewProjectSheet: $showingNewProjectSheet,
                showingProjectBrowser: $showingProjectBrowser,
                showingAboutWindow: $showingAboutWindow,
                showingCreateTrackDialog: $showingCreateTrackDialog,
                showingRenameTrackDialog: $showingRenameTrackDialog,
                renameTrackText: $renameTrackText,
                showingExportSettings: $showingExportSettings,
                activeSheet: $activeSheet,
                projectManager: projectManager,
                exportService: exportService,
                availableBuses: projectManager.currentProject?.buses ?? [],
                onCreateTracks: createTracks,
                onRenameTrack: performRenameTrack,
                onExportWithSettings: performExportWithSettings
            ))
            .sheet(isPresented: $showingMarketplaceSheet) {
                MarketplaceComingSoonView()
            }
            .sheet(isPresented: $showingWalletSheet) {
                WalletComingSoonView()
            }
            .sheet(isPresented: $showingTokenInput) {
                TokenInputView(allowDismiss: true)
            }
        .overlay {
            if exportService.isExporting {
                ExportProgressView(
                    progress: exportService.exportProgress,
                    status: exportService.exportStatus,
                    elapsedTime: exportService.elapsedTime,
                    estimatedTimeRemaining: exportService.estimatedTimeRemaining,
                    onCancel: {
                        exportService.cancelExport()
                    }
                )
            } else if !audioEngine.isGraphStable && projectManager.currentProject != nil {
                // Show loading overlay while audio graph is being built
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .controlSize(.large)
                        
                        Text("Loading Project...")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Restoring instruments and effects")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.3), radius: 20)
                    )
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: audioEngine.isGraphStable)
            }
        }
        .alert("Export Complete", isPresented: $showingExportAlert) {
            Button("OK") {
                showingExportAlert = false
            }
            Button("Show in Finder") {
                if let url = exportedFileURL {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                }
                showingExportAlert = false
            }
        } message: {
            if let url = exportedFileURL {
                Text("Your project has been exported to:\n\(url.lastPathComponent)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showingNewProjectSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { _ in
            showingProjectBrowser = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutWindow)) { _ in
            showingAboutWindow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanupOrphanedFiles)) { _ in
            projectManager.cleanupOrphanedAudioFiles()
        }
        // Time Display Mode toggle removed - beats is now the standard unit
        .onReceive(NotificationCenter.default.publisher(for: .toggleSnapToGrid)) { _ in
            setSnapToGrid(!snapToGrid)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWalletTab)) { _ in
            showingWalletSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMarketplace)) { _ in
            showingMarketplaceSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTokenInput)) { _ in
            showingTokenInput = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SetHorizontalZoom"))) { notification in
            if let zoom = notification.userInfo?["zoom"] as? Double {
                setHorizontalZoom(zoom)
            }
        }
        .modifier(MIDINotificationModifier(
            activeSheet: $activeSheet,
            onTogglePianoRoll: togglePianoRoll,
            onToggleSynthesizer: toggleSynthesizer,
            onToggleStepSequencer: toggleStepSequencer
        ))
        .notificationHandlers(
            projectManager: projectManager,
            audioEngine: audioEngine,
            selectedMainTab: $selectedMainTab,
            showingMixer: showingMixerBinding,
            showingInspector: showingInspectorBinding,
            showingSelection: showingSelectionBinding,
            showingStepSequencer: showingStepSequencerBinding,
            showingPianoRoll: showingPianoRollBinding,
            showingSynthesizer: showingSynthesizerBinding,
            showCreateTrackDialog: { showCreateTrackDialog() },
            addAudioTrack: { addTrack() },
            addMIDITrack: { addMIDITrack() },
            deleteSelectedTrack: deleteSelectedTrack,
            importAudio: importAudioToSelectedTrack,
            importMIDI: handleImportMIDIFile,
            saveProject: handleSaveProject,
            exportProject: handleExportProject,
            skipToBeginning: handleSkipToBeginning,
            skipToEnd: handleSkipToEnd
        )
        .onChange(of: projectManager.hasUnsavedChanges) { _, hasChanges in
            // Update window's document edited state (shows dot in close button)
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.isDocumentEdited = hasChanges
            }
        }
        .onAppear {
            // Configure AudioEngine with ProjectManager as single source of truth
            // CRITICAL: This must happen before any project loading
            audioEngine.configure(projectManager: projectManager)
            
            // Configure InstrumentManager with ProjectManager and AudioEngine for MIDI routing
            // CRITICAL: AudioEngine must be passed so samplers are attached to the correct engine
            InstrumentManager.shared.configure(with: projectManager, audioEngine: audioEngine)
            
            // Install metronome into DAW's audio graph for sample-accurate sync
            // This is idempotent - safe to call multiple times (handles engine restart if needed)
            audioEngine.installMetronome(metronomeEngine)
            
            // Sync metronome with project tempo
            if let project = projectManager.currentProject {
                metronomeEngine.tempo = project.tempo
                metronomeEngine.beatsPerBar = project.timeSignature.numerator
            }
            
            // NOTE: Automatic cleanup disabled - it was deleting audio files before project loaded
            // The cleanup runs BEFORE recentProjects is populated, so it can't know which files are referenced.
            // Files in temp directory persist until macOS clears them.
            // Manual cleanup is still available via File menu → Clean Up Orphaned Files
            // 
            // FUTURE FIX: Store audio files in project bundle with relative paths for proper persistence
            
            // MARK: - Automation Server
            // Enables external agents to control Stori via HTTP
            commandDispatcher = AICommandDispatcher(projectManager: projectManager, audioEngine: audioEngine)
            if let dispatcher = commandDispatcher {
                automationServer.configure(
                    composerClient: composerClient,
                    dispatcher: dispatcher,
                    projectManager: projectManager
                )
                automationServer.start()
            }
        }
        .task {
            // Give the audio engine a moment to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let project = projectManager.currentProject {
                    audioEngine.loadProject(project)
                } else {
                }
            }
        }
        .onChange(of: projectManager.currentProject) { oldProject, newProject in
            // Update audio engine when project changes
            if let newProj = newProject {
                let isDifferentProject = oldProject?.id != newProj.id
                if isDifferentProject {
                    // Different project: Full reload with track setup
                    audioEngine.loadProject(newProj)
                    
                    // Clear piano roll and editor state when switching projects
                    selectedMIDIRegion = nil
                    selectedMIDITrackId = nil
                    // Note: Piano roll visibility is now in project.uiState, restored by restoreUIState()
                    selectedTrackIds.removeAll()
                    selectedRegionId = nil
                    
                    // Select Track 1 by default (standard DAW behavior)
                    if let firstTrack = newProj.tracks.first {
                        selectedTrackId = firstTrack.id
                        audioEngine.selectedTrackId = firstTrack.id
                    }
                    
                    // 🎯 RESTORE COMPLETE UI STATE
                    // Restore all zoom, panels, tabs, metronome, playhead exactly as saved
                    restoreUIState()
                } else {
                    // Same project with updates (new regions, moved regions, etc.): Incremental update
                    // Pass oldProject so AudioEngine can detect what changed (since currentProject is now computed)
                    audioEngine.updateCurrentProject(newProj, previousProject: oldProject)
                }
                
                // Sync metronome with project tempo and time signature
                metronomeEngine.tempo = newProj.tempo
                metronomeEngine.beatsPerBar = newProj.timeSignature.numerator
            }
        }
        .onChange(of: audioEngine.transportState) { oldState, newState in
            // Sync metronome with transport state
            switch newState {
            case .playing:
                if metronomeEngine.isEnabled {
                    // Sync to current beat position and start
                    let currentBeatPosition = audioEngine.currentPosition.beats
                    metronomeEngine.onTransportSeek(to: currentBeatPosition)
                    metronomeEngine.onTransportPlay()
                }
            case .stopped, .paused:
                metronomeEngine.onTransportStop()
            case .recording:
                // For recording, count-in happens before record starts
                // The metronome continues during recording if enabled
                if metronomeEngine.isEnabled {
                    let currentBeatPosition = audioEngine.currentPosition.beats
                    metronomeEngine.onTransportSeek(to: currentBeatPosition)
                    metronomeEngine.onTransportPlay()
                }
            }
        }
        .onChange(of: selectedTrackId) { _, newTrackId in
            // Sync selected track to audio engine for "record-follows-selection" behavior
            // When no tracks are armed, recording goes to the selected track (standard DAW behavior)
            audioEngine.selectedTrackId = newTrackId
        }
        // PERFORMANCE: Inject @Observable AudioEngine for fine-grained SwiftUI updates
        // Views can use @Environment(AudioEngine.self) and only re-render when properties they READ change
        .environment(audioEngine)
    }
    
    // MARK: - Export Handler Methods
    
    private func handleSaveProject() {
        if projectManager.currentProject != nil {
            // Capture complete UI state before saving
            captureUIState()
            
            // Save the project with plugin sync (async)
            Task {
                await projectManager.performSaveWithPluginSync()
                
                // Capture screenshot of the main window for project thumbnail (async)
                captureProjectScreenshot()
            }
        }
    }
    
    // MARK: - External State Sync (MetronomeEngine, AudioEngine)
    // Note: UI state is now a single source of truth in project.uiState
    // Only external components need explicit sync
    
    /// Capture external state (metronome, playhead) into project before saving
    private func captureUIState() {
        guard var project = projectManager.currentProject else { return }
        
        // Capture metronome state (MetronomeEngine is external)
        project.uiState.metronomeEnabled = metronomeEngine.isEnabled
        project.uiState.metronomeVolume = metronomeEngine.volume
        
        // Capture playhead position (AudioEngine is external)
        project.uiState.playheadPosition = audioEngine.currentPosition.beats
        
        projectManager.currentProject = project
    }
    
    /// Restore external state (metronome, playhead) from project after loading
    private func restoreUIState() {
        guard let project = projectManager.currentProject else { return }
        let state = project.uiState
        
        // Restore metronome state to MetronomeEngine
        metronomeEngine.isEnabled = state.metronomeEnabled
        metronomeEngine.volume = state.metronomeVolume
        
        // Sync DAWUIState for keyboard capture
        DAWUIState.shared.isSynthesizerVisible = state.showingSynthesizer
        
        // Restore playback position (delay for audio engine initialization)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            audioEngine.seek(toBeat: state.playheadPosition)
        }
    }
    
    private func captureProjectScreenshot() {
        // Get the main window's content view
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView else {
            return
        }
        
        // Capture the screenshot
        projectManager.captureProjectScreenshot(from: contentView)
    }
    
    private func handleExportProject() {
        guard projectManager.currentProject != nil else {
            return
        }
        
        guard !exportService.isExporting else {
            return
        }
        
        // Show export settings sheet
        showingExportSettings = true
    }
    
    private func performExportWithSettings(_ settings: ExportSettings) {
        guard let project = projectManager.currentProject else { return }
        
        
        // Stop playback before exporting
        if audioEngine.transportState == .playing {
            audioEngine.stop()
        }
        
        // Perform export
        Task {
            do {
                let exportURL = try await exportService.exportProjectWithSettings(
                    project: project,
                    audioEngine: audioEngine,
                    settings: settings
                )
                
                await MainActor.run {
                    exportedFileURL = exportURL
                    showingExportAlert = true
                }
                
            } catch ExportError.formatFallback(_, let fallbackURL) {
                // Handle format fallback - still show success with note
                await MainActor.run {
                    exportedFileURL = fallbackURL
                    showingExportAlert = true
                }
            } catch {
                // Check if it was a cancellation
                if (error as? ExportError) == .cancelled {
                    // Don't show error alert for user cancellation
                } else {
                    
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    private func handleSkipToBeginning() {
        if projectManager.currentProject != nil && selectedMainTab == .daw {
            audioEngine.skipToBeginning()
        }
    }
    
    private func handleSkipToEnd() {
        if projectManager.currentProject != nil && selectedMainTab == .daw {
            audioEngine.skipToEnd()
        }
    }
}

extension MainDAWView {
    
    
    private var centerContentView: some View {
        VStack(spacing: 0) {
            // Timeline and tracks area - takes remaining space after bottom panels
            VStack(spacing: 0) {
                // Integrated Timeline with synchronized scrolling (zoom controls now in header)
                IntegratedTimelineView(
                    audioEngine: audioEngine,
                    projectManager: projectManager,
                    selectedTrackId: $selectedTrackId,
                    selectedTrackIds: $selectedTrackIds,
                    selectedRegionId: $selectedRegionId,
                    horizontalZoom: horizontalZoomBinding,
                    verticalZoom: verticalZoomBinding,
                    snapToGrid: snapToGridBinding,
                    catchPlayheadEnabled: catchPlayheadEnabled,
                    onAddTrack: { showCreateTrackDialog() },
                    onCreateProject: { showingNewProjectSheet = true },
                    onOpenProject: { showingProjectBrowser = true },
                    onSelectTrack: { trackId, modifiers in
                        selectTrack(trackId, modifiers: modifiers)
                    },
                    onDeleteTracks: {
                        deleteSelectedTracks()
                    },
                    onRenameTrack: { newName in
                        renameSelectedTrack(to: newName)
                    },
                    onNewAudioTrack: {
                        addTrack()
                    },
                    onNewMIDITrack: {
                        addMIDITrack()
                    },
                    onOpenPianoRoll: { midiRegion, track in
                        openPianoRollForRegion(midiRegion, on: track)
                    },
                    onBounceMIDIRegion: { midiRegion, track in
                        bounceMIDIRegionToAudio(midiRegion, on: track)
                    },
                    onDeleteMIDIRegion: { midiRegion, track in
                        deleteMIDIRegion(midiRegion, from: track)
                    }
                )
            }
            .frame(minHeight: 150) // Ensure timeline is always visible
            
            // Bottom area: Mixer panel (when visible)
            if showingMixer {
                mixerPanelView
            }
            
            // Bottom area: Step Sequencer panel (when visible)
            if showingStepSequencer {
                stepSequencerPanelView
            }
            
            // Bottom area: Piano Roll panel (when visible)
            if showingPianoRoll {
                pianoRollPanelView
            }
            
            // Bottom area: Synthesizer panel (when visible)
            if showingSynthesizer {
                synthesizerPanelView
            }
        }
    }
    
    private var pianoRollPanelView: some View {
        VStack(spacing: 0) {
            // Unified header with mode toggle and controls
            HStack(spacing: 12) {
                // Editor Mode Toggle - simple text-only buttons for clarity
                HStack(spacing: 0) {
                    Button(action: { setSelectedEditorMode(.pianoRoll) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pianokeys")
                                .font(.caption)
                            Text("Piano Roll")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedEditorMode == .pianoRoll
                                ? Color.accentColor
                                : Color(nsColor: .controlBackgroundColor)
                        )
                        .foregroundColor(selectedEditorMode == .pianoRoll ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { setSelectedEditorMode(.score) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note.list")
                                .font(.caption)
                            Text("Score")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedEditorMode == .score
                                ? Color.accentColor
                                : Color(nsColor: .controlBackgroundColor)
                        )
                        .foregroundColor(selectedEditorMode == .score ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(nsColor: .separatorColor).opacity(0.3))
                .cornerRadius(6)
                
                // Show region being edited
                if let region = selectedMIDIRegion {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(region.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("(\(region.notes.count) notes)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                Button(action: { setShowingPianoRoll(false) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Resize Handle
            ResizeHandle(
                orientation: .horizontal,
                onDrag: { delta in
                    // Allow up to 450px - leaves room for timeline and control bar
                    setPianoRollHeight(max(250, min(450, pianoRollHeight - delta)))
                }
            )
            
            // Content based on selected editor mode
            if selectedEditorMode == .pianoRoll {
                // Piano Roll Content - hide its internal header since we have a unified one above
                PianoRollPanelContent(
                    midiRegion: $selectedMIDIRegion,
                    trackId: selectedMIDITrackId ?? selectedTrackId,
                    projectManager: projectManager,
                    audioEngine: audioEngine,
                    showHeader: false,
                    snapToGrid: snapToGrid  // [PHASE-4] Pass snap toggle state
                )
                .frame(height: pianoRollHeight)
            } else {
                // Score Notation Content - Multi-track display
                let midiTracks = projectManager.currentProject?.tracks.filter { $0.isMIDITrack } ?? []
                
                if !midiTracks.isEmpty {
                    ScoreView(
                        region: Binding(
                            get: { selectedMIDIRegion ?? MIDIRegion(name: "Empty", duration: 4) },
                            set: { newRegion in
                                selectedMIDIRegion = newRegion
                                if let trackId = selectedMIDITrackId {
                                    projectManager.updateMIDIRegion(newRegion.id, on: trackId, notes: newRegion.notes)
                                }
                            }
                        ),
                        midiTracks: midiTracks,  // Pass all MIDI tracks for multi-staff display
                        tempo: projectManager.currentProject?.tempo ?? 120.0,
                        cycleEnabled: audioEngine.isCycleEnabled,
                        cycleStartBeat: audioEngine.cycleStartBeat,
                        cycleEndBeat: audioEngine.cycleEndBeat
                    )
                    .frame(height: pianoRollHeight)
                } else {
                    // No MIDI tracks
                    VStack {
                        Spacer()
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No MIDI tracks in project")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add a MIDI track to view the score")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        Spacer()
                    }
                    .frame(height: pianoRollHeight)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .transition(.move(edge: .bottom))
    }
    
    private var synthesizerPanelView: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                Text("Synthesizer")
                    .font(.headline)
                Spacer()
                Button(action: { setShowingSynthesizer(false) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Resize Handle
            ResizeHandle(
                orientation: .horizontal,
                onDrag: { delta in
                    // Allow up to 450px - leaves room for timeline and control bar
                    setSynthesizerHeight(max(200, min(450, synthesizerHeight - delta)))
                }
            )
            
            // Synthesizer Content
            SynthesizerPanelContent()
                .frame(height: synthesizerHeight)
        }
        .transition(.move(edge: .bottom))
    }
    
    private var stepSequencerPanelView: some View {
        VStack(spacing: 0) {
            // Visible top border for drag affordance
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)
            
            // Resize Handle with visible styling
            ResizeHandle(
                orientation: .horizontal,
                onDrag: { delta in
                    // Allow up to 450px - leaves room for timeline and control bar
                    setStepSequencerHeight(max(200, min(450, stepSequencerHeight - delta)))
                }
            )
            .background(Color(.windowBackgroundColor))
            
            // Step Sequencer Content
            StepSequencerView(sequencer: audioEngine.sequencerEngine, projectManager: projectManager, audioEngine: audioEngine, selectedTrackId: $selectedTrackId)
        }
        .frame(height: stepSequencerHeight)
        .transition(.move(edge: .bottom))
    }
    
    private var selectionPanelView: some View {
        HStack(spacing: 0) {
            // Selection panel content - reuse the inspector panel's selection logic
            SelectionPanelView(
                selectedTrackId: $selectedTrackId,
                selectedRegionId: $selectedRegionId,
                project: projectManager.currentProject,
                audioEngine: audioEngine,
                projectManager: projectManager
            )
            .frame(width: 300)
            
            // Resize Handle
            ResizeHandle(
                orientation: .vertical,
                onDrag: { delta in
                    // Future: allow resizing of selection panel
                }
            )
        }
        .transition(.move(edge: .leading))
    }
    
    private var rightPanelView: some View {
        HStack(spacing: 0) {
            // Resize Handle
            ResizeHandle(
                orientation: .vertical,
                onDrag: { delta in
                    setInspectorWidth(max(250, min(500, inspectorWidth - delta)))
                }
            )
            
            ComposerComingSoonView()
                .frame(width: inspectorWidth)
        }
        .transition(.move(edge: .trailing))
    }
    
    private var mixerPanelView: some View {
        VStack(spacing: 0) {
            // Visible top border for drag affordance
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)
            
            // Resize Handle with visible styling
            ResizeHandle(
                orientation: .horizontal,
                onDrag: { delta in
                    // Allow up to 450px height - leaves room for timeline and control bar
                    setMixerHeight(max(200, min(450, mixerHeight - delta)))
                }
            )
            .background(Color(.windowBackgroundColor))
            
            // Mixer Content
            MixerView(
                audioEngine: audioEngine,
                projectManager: projectManager,
                selectedTrackId: $selectedTrackId,
                isGraphStable: audioEngine.isGraphStable
            )
        }
        .frame(height: mixerHeight)
        .transition(.move(edge: .bottom))
    }
    
    private func dawContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Main content area with professional panel layout
            HStack(spacing: 0) {
                // Left Panel: Selection Info (when visible)
                if showingSelection {
                    selectionPanelView
                }
                
                // Center: Main DAW Content
                centerContentView
                
                // Right Panel: Inspector (when visible)
                if showingInspector {
                    rightPanelView
                }
            }
            
            // Professional DAW Control Bar - Pinned to Bottom
            DAWControlBar(
                audioEngine: audioEngine,
                projectManager: projectManager,
                metronomeEngine: metronomeEngine,
                showingMixer: showingMixerBinding,
                showingInspector: showingInspectorBinding,
                showingSelection: showingSelectionBinding,
                showingStepSequencer: showingStepSequencerBinding,
                showingPianoRoll: showingPianoRollBinding,
                showingSynthesizer: showingSynthesizerBinding,
                catchPlayheadEnabled: catchPlayheadEnabledBinding
            )
        }
        .animation(.easeInOut(duration: 0.3), value: showingInspector)
        .animation(.easeInOut(duration: 0.3), value: showingSelection)
        .animation(.easeInOut(duration: 0.3), value: showingMixer)
        .animation(.easeInOut(duration: 0.3), value: showingStepSequencer)
        .animation(.easeInOut(duration: 0.3), value: showingPianoRoll)
        .animation(.easeInOut(duration: 0.3), value: showingSynthesizer)
        .onChange(of: showingSynthesizer) { _, newValue in
            // Sync with DAWUIState for NSEvent handler access
            DAWUIState.shared.isSynthesizerVisible = newValue
        }
        .onChange(of: activeSheet) { _, newValue in
            // Sync virtual keyboard sheet state with DAWUIState for NSEvent handler access
            DAWUIState.shared.isVirtualKeyboardOpen = (newValue == .virtualKeyboard)
        }
        .onChange(of: selectedTrackId) { oldValue, newValue in
            
            // Update InstrumentManager so Virtual Keyboard routes to correct track
            InstrumentManager.shared.selectedTrackId = newValue
        }
        // Keyboard shortcuts for zoom, deletion, undo/redo
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Skip keyboard shortcuts if user is typing in a text field
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   firstResponder is NSTextView || firstResponder is NSTextField {
                    return event // Pass through to text field
                }
                
                // Delete/Backspace: Delete selected region(s)
                if event.keyCode == 51 || event.keyCode == 117 { // Delete or Forward Delete
                    // Check if any regions are selected (not tracks)
                    if selectedRegionId != nil {
                        handleDeleteSelectedRegion()
                        return nil // Consume the event
                    }
                }
                // Command + Z: Undo
                else if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers == "z" {
                    UndoService.shared.undo()
                    // Audio engine reload is handled by undo operations
                    return nil // Consume the event
                }
                // Command + Shift + Z: Redo
                else if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers == "z" {
                    UndoService.shared.redo()
                    // Audio engine reload is handled by redo operations
                    return nil // Consume the event
                }
                // Command + Plus/Equals: Zoom in horizontally
                else if event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
                    setHorizontalZoom(min(10.0, horizontalZoom + 0.2))
                    return nil // Consume the event
                }
                // Command + Minus: Zoom out horizontally
                else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "-" {
                    setHorizontalZoom(max(0.1, horizontalZoom - 0.2))
                    return nil // Consume the event
                }
                // Command + 0: Zoom to fit project
                else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "0" {
                    zoomToFitProject()
                    return nil // Consume the event
                }
                // Shift + Left Arrow: Nudge selected regions left by one bar
                else if event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) && event.keyCode == 123 {
                    NotificationCenter.default.post(name: .nudgeRegionsLeft, object: nil)
                    return nil // Consume the event
                }
                // Shift + Right Arrow: Nudge selected regions right by one bar
                else if event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) && event.keyCode == 124 {
                    NotificationCenter.default.post(name: .nudgeRegionsRight, object: nil)
                    return nil // Consume the event
                }
                // Tab: Select next region
                else if event.keyCode == 48 && !event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .selectNextRegion, object: nil)
                    return nil // Consume the event
                }
                // Shift + Tab: Select previous region
                else if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .selectPreviousRegion, object: nil)
                    return nil // Consume the event
                }
                // Up Arrow: Select region on track above
                else if event.keyCode == 126 && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .selectRegionAbove, object: nil)
                    return nil // Consume the event
                }
                // Down Arrow: Select region on track below
                else if event.keyCode == 125 && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .selectRegionBelow, object: nil)
                    return nil // Consume the event
                }
                // Z: Zoom to selection
                else if event.charactersIgnoringModifiers == "z" && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .zoomToSelection, object: nil)
                    return nil // Consume the event
                }
                // Command + Shift + Right Arrow: Go to next region
                else if event.keyCode == 124 && event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .goToNextRegion, object: nil)
                    return nil // Consume the event
                }
                // Command + Shift + Left Arrow: Go to previous region
                else if event.keyCode == 123 && event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .goToPreviousRegion, object: nil)
                    return nil // Consume the event
                }
                // Period (.): Move forward one beat
                else if event.charactersIgnoringModifiers == "." && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                    NotificationCenter.default.post(name: .moveBeatForward, object: nil)
                    return nil // Consume the event
                }
                // Comma (,): Move backward one beat
                else if event.charactersIgnoringModifiers == "," && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                    NotificationCenter.default.post(name: .moveBeatBackward, object: nil)
                    return nil // Consume the event
                }
                // Shift + Period: Move forward one bar
                else if event.charactersIgnoringModifiers == "." && event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                    NotificationCenter.default.post(name: .moveBarForward, object: nil)
                    return nil // Consume the event
                }
                // Shift + Comma: Move backward one bar
                else if event.charactersIgnoringModifiers == "," && event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                    NotificationCenter.default.post(name: .moveBarBackward, object: nil)
                    return nil // Consume the event
                }
                // 'a' (no modifiers): Toggle automation on selected track
                // Only when virtual keyboard/synthesizer is NOT visible to avoid capturing music keys
                // Note: We use DAWUIState.shared because NSEvent closures capture @State at creation time
                // Also skip if focus is in a text field (user is typing)
                else if event.charactersIgnoringModifiers == "a" && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) && !DAWUIState.shared.shouldCaptureMusicKeys {
                    // Check if first responder is a text field - don't capture 'a' if user is typing
                    if let firstResponder = NSApp.keyWindow?.firstResponder,
                       (firstResponder is NSTextView || firstResponder is NSTextField) {
                        return event // Let the text field handle it
                    }
                    if let trackId = selectedTrackId {
                        toggleAutomationOnTrack(trackId)
                        return nil // Consume the event
                    }
                }
                return event // Pass through other events
            }
        }
    }
    
    /// Zoom to fit the entire project in view (⌘0)
    private func zoomToFitProject() {
        guard let project = projectManager.currentProject else {
            // No project, reset to default
            setHorizontalZoom(1.0)
            return
        }
        
        // Get project duration in beats
        let durationBeats = project.durationBeats
        
        // Minimum project size: 32 bars (128 beats at 4/4)
        let minBeats: Double = 128
        let effectiveDurationBeats = max(minBeats, durationBeats + 16) // Add 16 beats (4 bars) padding
        
        // Estimate visible viewport width (window width minus sidebars and track headers)
        // Track headers: ~350px, Inspector/Library: ~280px, margins: ~50px
        // Assume typical window width of ~1400px -> viewport ~720px
        // For larger screens, use NSScreen to get actual width
        let screenWidth = NSScreen.main?.frame.width ?? 1400
        let estimatedViewportWidth = max(600, screenWidth - 700) // 700px for UI elements
        
        // Calculate zoom: pixelsPerBeat = 40 * horizontalZoom
        // We want: effectiveDurationBeats * (40 * zoom) = viewportWidth
        // So: zoom = viewportWidth / (effectiveDurationBeats * 40)
        let basePixelsPerBeat: Double = 40
        let calculatedZoom = estimatedViewportWidth / (effectiveDurationBeats * basePixelsPerBeat)
        
        // Clamp to reasonable range (0.1 to 10.0)
        setHorizontalZoom(min(10.0, max(0.1, calculatedZoom)))
    }
    
    /// Toggle automation expanded state on the specified track
    private func toggleAutomationOnTrack(_ trackId: UUID) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        project.tracks[trackIndex].automationExpanded.toggle()
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
}

// MARK: - Timeline Ruler View (Removed - now integrated within IntegratedTimelineView)

// MARK: - Selection Panel View

struct SelectionPanelView: View {
    @Binding var selectedTrackId: UUID?
    @Binding var selectedRegionId: UUID?
    let project: AudioProject?
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Selection")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Selection content
            ScrollView {
                VStack(spacing: 16) {
                    if let regionId = selectedRegionId,
                       let project = project,
                       let region = findRegion(withId: regionId, in: project) {
                        // Show region details
                        Text("Region: \(region.audioFile.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let trackId = selectedTrackId,
                              let project = project,
                              let track = project.tracks.first(where: { $0.id == trackId }) {
                        // Show track details
                        Text("Track: \(track.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No Selection")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("Select a region or track to view its properties.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
    }
    
    private func findRegion(withId id: UUID, in project: AudioProject) -> AudioRegion? {
        for track in project.tracks {
            if let region = track.regions.first(where: { $0.id == id }) {
                return region
            }
        }
        return nil
    }
}

// MARK: - Supporting Views
struct NewProjectView: View {
    var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = "Untitled"
    @State private var tempo: Double = 120
    @State private var timeSignature = TimeSignature.fourFour
    @State private var sampleRate: Double = 48000
    @State private var animateGradient = false
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6),
                    Color.pink.opacity(0.4)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .frame(height: 120)
            .overlay(
                VStack(spacing: 12) {
                    // Project icon with glow effect
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    // Title with gradient text
                    Text("New Project")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            
            // Form content with enhanced styling
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    // Project Name with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("Project Name")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("Enter project name", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // BPM with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "metronome")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                            Text("Tempo (BPM)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("120", value: $tempo, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sample Rate with icon (fixed to 48 kHz - device native)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(.pink)
                            Text("Sample Rate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        // Fixed to 48 kHz - matches audio engine device format
                        HStack {
                            Text("48 kHz")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                            Spacer()
                            Text("(Fixed)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor).opacity(0.5))
                                .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                
                Spacer()
                
                // Enhanced buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .keyboardShortcut(.escape, modifiers: [])  // Enable Escape key
                    
                    Button(action: createProject) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text(isCreating ? "Creating..." : "Create Project")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])  // Enable Enter key
                    .disabled(isCreating || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private func createProject() {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        
        // Add a small delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                try projectManager.createNewProject(
                    name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                    tempo: tempo
                )
                dismiss()
            } catch {
                isCreating = false
                // Show error message to user
                if let projectError = error as? ProjectError {
                    // You could show an alert here or set an error state
                    // For now, we'll just print the error
                    // In a production app, you'd want to show this to the user
                } else {
                }
            }
        }
    }
    
    private var sampleRateText: String {
        switch sampleRate {
        case 44100: return "44.1 kHz"
        case 48000: return "48 kHz"
        case 96000: return "96 kHz"
        default: return "\(Int(sampleRate/1000)) kHz"
        }
    }
}

// MARK: - Reusable Recent Projects List
struct RecentProjectsListView: View {
    var projectManager: ProjectManager
    let onProjectSelected: ((AudioProject) -> Void)?
    let showHeader: Bool
    let compactMode: Bool
    
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    init(
        projectManager: ProjectManager, 
        onProjectSelected: ((AudioProject) -> Void)? = nil,
        showHeader: Bool = false,
        compactMode: Bool = false
    ) {
        self.projectManager = projectManager
        self.onProjectSelected = onProjectSelected
        self.showHeader = showHeader
        self.compactMode = compactMode
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                // Header
                HStack {
                    Text("Recent Projects")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .bottom
                )
            }
            
            // Projects List
            if projectManager.recentProjects.isEmpty {
                if compactMode {
                    // Enhanced empty state for compact mode (EmptyTimelineView)
                    VStack(spacing: 32) {
                        Spacer()
                        
                        // Header with icon
                        VStack(spacing: 16) {
                            // Gradient icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "clock")
                                    .font(.system(size: 48, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            // Title and subtitle
                            VStack(spacing: 8) {
                                Text("No Recent Projects")
                                    .font(.system(size: 28, weight: .semibold))
                                
                                Text("Your recently opened projects will appear here for quick access")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 500)
                            }
                        }
                        
                        // Feature highlights
                        VStack(alignment: .leading, spacing: 20) {
                            RecentFeatureRow(
                                icon: "arrow.counterclockwise",
                                title: "Quick Access",
                                description: "Jump back into your recent work instantly"
                            )
                            
                            RecentFeatureRow(
                                icon: "clock.arrow.circlepath",
                                title: "Auto-Tracked",
                                description: "Projects are automatically added when you open them"
                            )
                            
                            RecentFeatureRow(
                                icon: "list.bullet",
                                title: "Project History",
                                description: "See project details and last modified dates"
                            )
                            
                            RecentFeatureRow(
                                icon: "trash",
                                title: "Easy Management",
                                description: "Remove projects from the list or delete them entirely"
                            )
                        }
                        .frame(maxWidth: 500)
                        
                        Spacer()
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Simple empty state for non-compact mode
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Recent Projects")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("Create a new project to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: compactMode ? 8 : 1) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectRowView(
                                project: project,
                                compactMode: compactMode,
                                onSelect: {
                                    onProjectSelected?(project)
                                },
                                onDelete: {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding(compactMode ? 16 : 0)
                }
                .background(Color(compactMode ? .clear : NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            projectManager.loadRecentProjects()
        }
        .alert("Delete Project", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    projectManager.deleteProject(project)
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This action cannot be undone.")
            }
        }
    }
}

struct ProjectBrowserView: View {
    var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProject: AudioProject?
    @State private var hoveredProject: AudioProject?
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose a Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            // Project Grid
            if projectManager.recentProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Recent Projects")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Create a new project to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 20)
                    ], spacing: 20) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectThumbnailCard(
                                project: project,
                                projectManager: projectManager,
                                isSelected: selectedProject?.id == project.id,
                                isHovered: hoveredProject?.id == project.id,
                                onSelect: {
                                    selectedProject = project
                                },
                                onOpen: {
                                    projectManager.loadProject(project)
                                    dismiss()
                                },
                                onDelete: {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                },
                                onHover: { hovering in
                                    hoveredProject = hovering ? project : nil
                                }
                            )
                        }
                    }
                    .padding(24)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // Bottom bar with selected project info
            if let selected = selectedProject {
                HStack {
                    Text(selected.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Choose") {
                        projectManager.loadProject(selected)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction) // Responds to Return key
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .top
                )
            }
        }
        .frame(width: 920, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            projectManager.loadRecentProjects()
        }
        .alert("Delete Project", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    projectManager.deleteProject(project)
                    if selectedProject?.id == project.id {
                        selectedProject = nil
                    }
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This action cannot be undone.")
            }
        }
    }
}

// MARK: - Project Thumbnail Card
struct ProjectThumbnailCard: View {
    let project: AudioProject
    let projectManager: ProjectManager
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail/Preview
            ZStack {
                // Try to load actual screenshot, fall back to gradient placeholder
                if let thumbnailURL = projectManager.getProjectThumbnailURL(for: project),
                   let nsImage = NSImage(contentsOf: thumbnailURL) {
                    // Display actual screenshot
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Fallback: gradient placeholder
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.6),
                                Color.purple.opacity(0.5),
                                Color.pink.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Waveform pattern overlay
                        VStack(spacing: 8) {
                            ForEach(0..<5) { index in
                                HStack(spacing: 4) {
                                    ForEach(0..<12) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 3, height: CGFloat.random(in: 10...35))
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                // Delete button (shows on hover)
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDelete) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.red.opacity(0.9))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            
            // Project Info
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text("Modified: \(relativeTimeString(from: project.modifiedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                onOpen()
            } else {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                onHover(hovering)
            }
        }
        .contextMenu {
            Button("Open Project") {
                onOpen()
            }
            
            Divider()
            
            Button("Delete Project", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        
        if days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Project Row View
struct ProjectRowView: View {
    let project: AudioProject
    let compactMode: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    init(project: AudioProject, compactMode: Bool = false, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.project = project
        self.compactMode = compactMode
        self.onSelect = onSelect
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack(spacing: compactMode ? 12 : 16) {
            // Project Icon
            RoundedRectangle(cornerRadius: compactMode ? 6 : 8)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: compactMode ? 40 : 48, height: compactMode ? 40 : 48)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: compactMode ? 16 : 20, weight: .medium))
                        .foregroundColor(.white)
                )
            
            // Project Info
            VStack(alignment: .leading, spacing: compactMode ? 2 : 4) {
                Text(project.name)
                    .font(.system(size: compactMode ? 14 : 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                    .font(.system(size: compactMode ? 12 : 13))
                    .foregroundColor(.secondary)
                
                if !compactMode {
                    Text("Modified: \(relativeTimeString(from: project.modifiedAt))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Project")
                    .transition(.opacity.combined(with: .scale))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open Project") {
                onSelect()
            }
            
            Divider()
            
            Button("Delete Project", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        
        if days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Resizable Panel Handle
struct ResizeHandle: View {
    enum Orientation {
        case horizontal, vertical
    }
    
    let orientation: Orientation
    let onDrag: (CGFloat) -> Void
    
    @State private var isHovered = false
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(isHovered || isDragging ? Color.accentColor.opacity(0.3) : Color(.windowBackgroundColor))
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            
            // Always-visible grip indicator
            if orientation == .horizontal {
                // Horizontal grip dots
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(isHovered || isDragging ? Color.accentColor : Color(.separatorColor))
                            .frame(width: 4, height: 4)
                    }
                }
            } else {
                // Vertical grip dots
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(isHovered || isDragging ? Color.accentColor : Color(.separatorColor))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(
            width: orientation == .vertical ? 10 : nil,
            height: orientation == .horizontal ? 10 : nil
        )
        .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    let delta = orientation == .vertical ? value.translation.width : value.translation.height
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Custom Cursor Extension for Resize Handles
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Custom Cursors
extension NSCursor {
    /// Custom loop/repeat cursor using SF Symbol (black is beautiful ⚫️)
    static var loop: NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbolImage = NSImage(systemSymbolName: "arrow.circlepath", accessibilityDescription: "Loop")?
            .withSymbolConfiguration(config) else {
            return .crosshair
        }
        
        let hotSpot = NSPoint(x: symbolImage.size.width / 2, y: symbolImage.size.height / 2)
        return NSCursor(image: symbolImage, hotSpot: hotSpot)
    }
    
    /// Custom regenerate cursor for AI-generated regions
    static var regenerate: NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbolImage = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Regenerate")?
            .withSymbolConfiguration(config) else {
            return .crosshair
        }
        
        let hotSpot = NSPoint(x: symbolImage.size.width / 2, y: symbolImage.size.height / 2)
        return NSCursor(image: symbolImage, hotSpot: hotSpot)
    }
}

// MARK: - View Extension for Notification Handlers
extension View {
    func notificationHandlers(
        projectManager: ProjectManager,
        audioEngine: AudioEngine,
        selectedMainTab: Binding<MainTab>,
        showingMixer: Binding<Bool>,
        showingInspector: Binding<Bool>,
        showingSelection: Binding<Bool>,
        showingStepSequencer: Binding<Bool>,
        showingPianoRoll: Binding<Bool>,
        showingSynthesizer: Binding<Bool>,
        showCreateTrackDialog: @escaping () -> Void,
        addAudioTrack: @escaping () -> Void,
        addMIDITrack: @escaping () -> Void,
        deleteSelectedTrack: @escaping () -> Void,
        importAudio: @escaping () -> Void,
        importMIDI: @escaping () -> Void,
        saveProject: @escaping () -> Void,
        exportProject: @escaping () -> Void,
        skipToBeginning: @escaping () -> Void,
        skipToEnd: @escaping () -> Void
    ) -> some View {
        self.modifier(
            NotificationHandlersModifier(
                projectManager: projectManager,
                audioEngine: audioEngine,
                selectedMainTab: selectedMainTab,
                showingMixer: showingMixer,
                showingInspector: showingInspector,
                showingSelection: showingSelection,
                showingStepSequencer: showingStepSequencer,
                showingPianoRoll: showingPianoRoll,
                showingSynthesizer: showingSynthesizer,
                showCreateTrackDialog: showCreateTrackDialog,
                addAudioTrack: addAudioTrack,
                addMIDITrack: addMIDITrack,
                deleteSelectedTrack: deleteSelectedTrack,
                importAudio: importAudio,
                importMIDI: importMIDI,
                saveProject: saveProject,
                exportProject: exportProject,
                skipToBeginning: skipToBeginning,
                skipToEnd: skipToEnd
            )
        )
    }
}

// MARK: - Notification Handlers Modifier
struct NotificationHandlersModifier: ViewModifier {
    let projectManager: ProjectManager
    let audioEngine: AudioEngine
    let selectedMainTab: Binding<MainTab>
    let showingMixer: Binding<Bool>
    let showingInspector: Binding<Bool>
    let showingSelection: Binding<Bool>
    let showingStepSequencer: Binding<Bool>
    let showingPianoRoll: Binding<Bool>
    let showingSynthesizer: Binding<Bool>
    let showCreateTrackDialog: () -> Void
    let addAudioTrack: () -> Void
    let addMIDITrack: () -> Void
    let deleteSelectedTrack: () -> Void
    let importAudio: () -> Void
    let importMIDI: () -> Void
    let saveProject: () -> Void
    let exportProject: () -> Void
    let skipToBeginning: () -> Void
    let skipToEnd: () -> Void
    
    func body(content: Content) -> some View {
        content
            .modifier(TrackNotificationsModifier(
                onNewTrackDialog: handleNewTrackDialog,
                onNewAudioTrack: handleNewAudioTrack,
                onNewMIDITrack: handleNewMIDITrack,
                onDeleteTrack: handleDeleteTrack,
                onImportAudio: handleImportAudio,
                onImportMIDI: handleImportMIDIFile
            ))
            .modifier(PanelNotificationsModifier(
                onToggleMixer: handleToggleMixer,
                onToggleInspector: handleToggleInspector,
                onToggleSelection: handleToggleSelection,
                onOpenTrackInspector: handleOpenTrackInspector,
                onOpenRegionInspector: handleOpenRegionInspector,
                onOpenProjectInspector: handleOpenProjectInspector
            ))
            // .modifier(TabNotificationsModifier(
            //     onOpenChatTab: handleOpenChatTab,
            //     onOpenVisualTab: handleOpenVisualTab
            // ))
            .modifier(ProjectNotificationsModifier(
                audioEngine: audioEngine,
                onSaveProject: saveProject,
                onExportProject: exportProject,
                onSkipToBeginning: skipToBeginning,
                onSkipToEnd: skipToEnd
            ))
    }
    
    // MARK: - Handler Methods
    
    private func handleNewTrackDialog() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            showCreateTrackDialog()
        }
    }
    
    private func handleNewAudioTrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            addAudioTrack()
        }
    }
    
    private func handleNewMIDITrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            addMIDITrack()
        }
    }
    
    private func handleDeleteTrack() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            deleteSelectedTrack()
        }
    }
    
    private func handleImportAudio() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            importAudio()
        }
    }
    
    private func handleImportMIDIFile() {
        if projectManager.currentProject != nil && selectedMainTab.wrappedValue == .daw {
            importMIDI()
        }
    }
    
    private func handleToggleMixer() {
        if selectedMainTab.wrappedValue == .daw {
            if showingMixer.wrappedValue {
                showingMixer.wrappedValue = false
            } else {
                // Close all other bottom panels
                showingStepSequencer.wrappedValue = false
                showingPianoRoll.wrappedValue = false
                showingSynthesizer.wrappedValue = false
                showingMixer.wrappedValue = true
            }
        }
    }
    
    private func handleToggleInspector() {
        showingInspector.wrappedValue.toggle()
    }
    
    private func handleToggleSelection() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue.toggle()
        }
    }
    
    private func handleOpenTrackInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
    
    private func handleOpenRegionInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
    
    private func handleOpenProjectInspector() {
        if selectedMainTab.wrappedValue == .daw {
            showingSelection.wrappedValue = true
        }
    }
    
    // Temporarily disabled - Visual and Chat tabs commented out
    // private func handleOpenChatTab() {
    //     if selectedMainTab.wrappedValue == .daw {
    //         showingInspector.wrappedValue = true
    //         selectedInspectorTab.wrappedValue = .chat
    //     }
    // }
    // 
    // private func handleOpenVisualTab() {
    //     if selectedMainTab.wrappedValue == .daw {
    //         showingInspector.wrappedValue = true
    //         selectedInspectorTab.wrappedValue = .visual
    //     }
    // }
    
}

// MARK: - Track Notifications Modifier
struct TrackNotificationsModifier: ViewModifier {
    let onNewTrackDialog: () -> Void
    let onNewAudioTrack: () -> Void
    let onNewMIDITrack: () -> Void
    let onDeleteTrack: () -> Void
    let onImportAudio: () -> Void
    let onImportMIDI: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTrackDialog)) { _ in
                onNewTrackDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTrack)) { _ in
                onNewTrackDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newAudioTrack)) { _ in
                onNewAudioTrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newMIDITrack)) { _ in
                onNewMIDITrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteTrack)) { _ in
                onDeleteTrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importAudio)) { _ in
                onImportAudio()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importMIDIFile)) { _ in
                onImportMIDI()
            }
    }
}

// MARK: - Panel Notifications Modifier
struct PanelNotificationsModifier: ViewModifier {
    let onToggleMixer: () -> Void
    let onToggleInspector: () -> Void
    let onToggleSelection: () -> Void
    let onOpenTrackInspector: () -> Void
    let onOpenRegionInspector: () -> Void
    let onOpenProjectInspector: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleMixer)) { _ in
                onToggleMixer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                onToggleInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSelection)) { _ in
                onToggleSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTrackInspector)) { _ in
                onOpenTrackInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRegionInspector)) { _ in
                onOpenRegionInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProjectInspector)) { _ in
                onOpenProjectInspector()
            }
    }
}

// MARK: - Tab Notifications Modifier
struct TabNotificationsModifier: ViewModifier {
    let onOpenChatTab: () -> Void
    let onOpenVisualTab: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openChatTab)) { _ in
                onOpenChatTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openVisualTab)) { _ in
                onOpenVisualTab()
            }
    }
}

// MARK: - Project Notifications Modifier
struct ProjectNotificationsModifier: ViewModifier {
    let audioEngine: AudioEngine
    let onSaveProject: () -> Void
    let onExportProject: () -> Void
    let onSkipToBeginning: () -> Void
    let onSkipToEnd: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .saveProject)) { _ in
                onSaveProject()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportProject)) { _ in
                onExportProject()
            }
            .onReceive(NotificationCenter.default.publisher(for: .skipToBeginning)) { _ in
                onSkipToBeginning()
            }
            .onReceive(NotificationCenter.default.publisher(for: .skipToEnd)) { _ in
                onSkipToEnd()
            }
            // Transport controls from menu
            .onReceive(NotificationCenter.default.publisher(for: .playPause)) { _ in
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.play()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stop)) { _ in
                if audioEngine.isRecording {
                    audioEngine.stopRecording()
                } else {
                    audioEngine.stop()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .record)) { _ in
                if !audioEngine.isRecording {
                    audioEngine.record()
                }
            }
    }
}

// MARK: - DAW Sheet Content View

struct DAWSheetContent: View {
    let sheet: DAWSheet
    
    var body: some View {
        switch sheet {
        case .virtualKeyboard:
            VirtualKeyboardView()
        }
    }
}

// MARK: - MIDI Notification Modifier

struct MIDINotificationModifier: ViewModifier {
    @Binding var activeSheet: DAWSheet?
    let onTogglePianoRoll: () -> Void
    let onToggleSynthesizer: () -> Void
    let onToggleStepSequencer: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleVirtualKeyboard)) { _ in
                if activeSheet == .virtualKeyboard {
                    activeSheet = nil
                } else {
                    activeSheet = .virtualKeyboard
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePianoRoll)) { _ in
                onTogglePianoRoll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSynthesizer)) { _ in
                onToggleSynthesizer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStepSequencer)) { _ in
                onToggleStepSequencer()
            }
    }
}

// MARK: - DAW Sheet Modifiers

struct DAWSheetModifiers: ViewModifier {
    @Binding var showingNewProjectSheet: Bool
    @Binding var showingProjectBrowser: Bool
    @Binding var showingAboutWindow: Bool
    @Binding var showingCreateTrackDialog: Bool
    @Binding var showingRenameTrackDialog: Bool
    @Binding var renameTrackText: String
    @Binding var showingExportSettings: Bool
    @Binding var activeSheet: DAWSheet?
    
    let projectManager: ProjectManager
    let exportService: ProjectExportService
    let availableBuses: [MixerBus]
    let onCreateTracks: (NewTrackConfig) async -> Void
    let onRenameTrack: () -> Void
    let onExportWithSettings: (ExportSettings) -> Void
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectView(projectManager: projectManager)
            }
            .sheet(isPresented: $showingProjectBrowser) {
                ProjectBrowserView(projectManager: projectManager)
            }
            .sheet(isPresented: $showingAboutWindow) {
                AboutView()
            }
            .sheet(isPresented: $showingCreateTrackDialog) {
                CreateTrackDialog(
                    isPresented: $showingCreateTrackDialog,
                    availableBuses: availableBuses,
                    onCreateTracks: onCreateTracks
                )
            }
            .sheet(isPresented: $showingRenameTrackDialog) {
                RenameTrackDialog(trackName: $renameTrackText, onRename: onRenameTrack)
            }
            .sheet(isPresented: $showingExportSettings) {
                let project = self.projectManager.currentProject
                let duration = project.map { self.exportService.calculateProjectDuration($0) } ?? 0
                
                ExportSettingsSheet(
                    projectName: project?.name ?? "Untitled",
                    projectDuration: duration,
                    onExport: onExportWithSettings
                )
            }
            .sheet(item: $activeSheet) { sheet in
                DAWSheetContent(sheet: sheet)
            }
    }
}

// MARK: - Recent Feature Row Component
struct RecentFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
