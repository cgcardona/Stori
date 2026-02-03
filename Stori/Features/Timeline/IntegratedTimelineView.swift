//
//  IntegratedTimelineView.swift
//  Stori
//
//  Integrated timeline combining synchronized scrolling with full TellUrStori functionality
//  Merges layout-test-1 scroll sync with existing AudioEngine, project management, and DAW features
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Combine

// MARK: - Time Display Mode (Internal to Timeline)

/// Snap/grid behavior for regions. Timeline is beat-based only; legacy time mode removed.
enum TimeDisplayMode: String {
    case beats = "Beats"
}

struct IntegratedTimelineView: View {
    // PERFORMANCE: AudioEngine is now @Observable - fine-grained updates only
    // Views only re-render when the specific properties they READ change
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    
    // [V2-ANALYSIS] Audio analysis service for tempo/pitch detection
    @State private var analysisService = AudioAnalysisService()
    
    // [V2-EXPORT] Audio export service for before/after comparison
    @State private var exportService = AudioExportService()
    
    // Computed property to get current project reactively
    private var project: AudioProject? { projectManager.currentProject }
    @Binding var selectedTrackId: UUID?
    @Binding var selectedTrackIds: Set<UUID>
    @Binding var selectedRegionId: UUID?
    // MIDI selection now managed by SelectionManager for fine-grained updates
    @State private var selection = SelectionManager() // [V2-MULTISELECT] - also manages MIDI selection
    @Binding var horizontalZoom: Double
    @Binding var verticalZoom: Double
    @Binding var snapToGrid: Bool
    var catchPlayheadEnabled: Bool = true  // Auto-scroll to follow playhead
    
    /// Time display mode - always beats (standardized throughout the app)
    private var timeDisplayMode: TimeDisplayMode { .beats }
    
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    let onSelectTrack: (UUID, EventModifiers) -> Void
    let onDeleteTracks: () -> Void
    let onRenameTrack: (String) -> Void
    let onNewAudioTrack: () -> Void
    let onNewMIDITrack: () -> Void
    
    // MIDI region editing callbacks
    var onOpenPianoRoll: ((MIDIRegion, AudioTrack) -> Void)?
    var onBounceMIDIRegion: ((MIDIRegion, AudioTrack) -> Void)?
    var onDeleteMIDIRegion: ((MIDIRegion, AudioTrack) -> Void)?
    
    // Scroll synchronization model
    @State private var scrollSync = ScrollSyncModel()
    
    // [PHASE-8] Viewport dimensions for MIDI note culling
    @State private var viewportWidth: CGFloat = 1200
    
    // Catch playhead tracking - stores the beat position when user last manually scrolled
    @State private var lastCatchBeat: Double = 0
    
    // Drag-and-drop state
    @State private var isDragOver = false
    @State private var dropTargetTrackId: UUID?
    // Tokenization state
    @State private var showingTokenizeSheet = false
    @State private var showingWalletConnection = false
    
    // MARK: - Batch Analysis HUD State
    @State private var showAnalysisHUD = false
    @State private var batchAnalysisState = BatchAnalysisState()
    
    // MARK: - Region Management
    
    /// Move an audio region to a new start beat on the timeline
    private func moveRegion(regionId: UUID, newStartBeat: Double) {
        // Capture old project state for comparison
        guard let oldProject = projectManager.currentProject else { return }
        var project = oldProject
        
        // Find the track and region to update
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                // 📊 COMPREHENSIVE LOGGING: Region movement
                
                // Update the region's start beat
                project.tracks[trackIndex].regions[regionIndex].startBeat = newStartBeat
                project.modifiedAt = Date()
                
                // Update the project manager
                projectManager.currentProject = project
                
                // Save the project to persist changes
                projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                
                // Update audio engine with new region position (preserves playhead position)
                // updateCurrentProject handles region moves without stopping playback
                audioEngine.updateCurrentProject(project, previousProject: oldProject)
                
                break
            }
        }
    }
    
    /// Move a region from one track to another
    private func moveRegionToTrack(regionId: UUID, fromTrackId: UUID, toTrackId: UUID, newStartBeat: Double) {
        // Capture old project state for comparison
        guard let oldProject = projectManager.currentProject else { return }
        var project = oldProject
        
        // Find and remove region from source track
        guard let fromTrackIndex = project.tracks.firstIndex(where: { $0.id == fromTrackId }),
              let regionIndex = project.tracks[fromTrackIndex].regions.firstIndex(where: { $0.id == regionId }) else {
            return
        }
        
        var region = project.tracks[fromTrackIndex].regions[regionIndex]
        
        // 📊 COMPREHENSIVE LOGGING: Cross-track movement
        
        project.tracks[fromTrackIndex].regions.remove(at: regionIndex)
        
        // Update region start beat and add to target track
        region.startBeat = newStartBeat
        
        guard let toTrackIndex = project.tracks.firstIndex(where: { $0.id == toTrackId }) else {
            return
        }
        
        project.tracks[toTrackIndex].regions.append(region)
        project.modifiedAt = Date()
        
        // Update project
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine with new region position (preserves playhead position)
        // updateCurrentProject handles cross-track moves without stopping playback
        audioEngine.updateCurrentProject(project, previousProject: oldProject)
        
    }
    
    // MARK: - Automation Lane Management
    
    /// Update an automation lane in the project
    private func updateAutomationLane(trackId: UUID, lane: AutomationLane) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == lane.id }) else {
            return
        }
        
        project.tracks[trackIndex].automationLanes[laneIndex] = lane
        project.modifiedAt = Date()
        projectManager.currentProject = project
        
        // Update audio engine automation processor
        audioEngine.updateTrackAutomation(project.tracks[trackIndex])
    }
    
    // MARK: - File Import via Drag-and-Drop
    
    /// Handle dropped audio files from Finder
    private func handleFileDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        guard let project = projectManager.currentProject else { return false }
        
        // Find which track the file was dropped on
        let trackIndex = Int(location.y / effectiveTrackHeight)
        guard trackIndex >= 0 && trackIndex < project.tracks.count else {
            return false
        }
        
        let targetTrack = project.tracks[trackIndex]
        
        // Calculate beat position from x coordinate
        let beatPosition = max(0, location.x / pixelsPerBeat)
        
        
        // Find .wav file provider
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.wav.identifier) }) else {
            return false
        }
        
        // Load the file - try as URL first, then as Data
        provider.loadItem(forTypeIdentifier: UTType.wav.identifier, options: nil) { (item, error) in
            if let error = error {
                return
            }
            
            var fileURL: URL?
            
            // Try to get URL directly (most common case for file drops)
            if let url = item as? URL {
                fileURL = Self.isValidAudioDropURL(url) ? url : nil
            }
            // Try to get URL from Data (bookmark or path data)
            else if let data = item as? Data {
                if let url = URL(dataRepresentation: data, relativeTo: nil) {
                    fileURL = Self.isValidAudioDropURL(url) ? url : nil
                } else if let path = String(data: data, encoding: .utf8),
                          !path.contains(".."),
                          path.count < 1024 {
                    let url = URL(fileURLWithPath: path)
                    fileURL = Self.isValidAudioDropURL(url) ? url : nil
                }
            }
            // Try NSURL
            else if let nsurl = item as? NSURL, let url = nsurl as URL? {
                fileURL = Self.isValidAudioDropURL(url) ? url : nil
            }

            guard let url = fileURL else {
                return
            }
            
            // Import the audio file (position in beats)
            DispatchQueue.main.async {
                self.importAudioFile(url: url, toTrack: targetTrack.id, atBeat: beatPosition)
            }
        }
        
        return true
    }
    
    /// Import an audio file and create an AudioRegion
    private func importAudioFile(url: URL, toTrack trackId: UUID, atBeat startBeat: Double) {
        do {
            // Enforce size limit before opening (prevents memory exhaustion)
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSizeAttr = fileAttributes[.size] as? Int64 ?? 0
            guard fileSizeAttr <= AudioEngine.maxAudioImportFileSize else {
                return // File too large
            }
            // Read audio file metadata
            let audioFile = try AVAudioFile(forReading: url)
            let durationSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            let sampleRate = audioFile.fileFormat.sampleRate
            let channels = Int(audioFile.fileFormat.channelCount)
            let fileSize = fileSizeAttr
            
            
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
            let tempo = projectManager.currentProject?.tempo ?? 120.0
            let durationBeats = durationSeconds * (tempo / 60.0)
            let region = AudioRegion(
                audioFile: audioFileModel,
                startBeat: startBeat,
                durationBeats: durationBeats,
                tempo: tempo,
                isLooped: false,
                offset: 0.0
            )
            
            // Add region to track
            projectManager.addRegionToTrack(region, trackId: trackId)
            
            
        } catch {
        }
    }

    /// Validates URL from drag-and-drop before import (path traversal, existence, audio extension).
    private static func isValidAudioDropURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.contains("..") || path.contains("//") { return false }
        let ext = url.pathExtension.lowercased()
        let validExts = ["wav", "aiff", "aif", "mp3", "m4a", "flac", "caf"]
        guard validExts.contains(ext) else { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }

    // TEMP: Build-unblock wrappers. These will be replaced by the Environment actions.
    private func matchTempoToRegion(_ targetRegionId: UUID) {
        // TODO: wire to real analysis
    }
    
    private func matchPitchToRegion(_ targetRegionId: UUID) {
        // TODO: wire to real analysis
    }
    
    private func autoMatchSelectedRegions() {
        // TODO: wire to real analysis
    }
    
    private let headerWidth: CGFloat = 348  // Track header width (3px leading + 23 + 44 + 122 + 88 + 52 + 2*6px spacing + 3px trailing)
    private let rulerHeight: CGFloat = 60
    private let trackRowHeight: CGFloat = 90
    
    // Dynamic sizing based on zoom
    private var effectiveTrackHeight: CGFloat { trackRowHeight * CGFloat(verticalZoom) }
    
    // Automation-expanded tracks are taller
    private let automationExpandedMultiplier: CGFloat = 1.6
    
    /// Get height for a specific track (taller when automation is expanded)
    private func heightForTrack(_ track: AudioTrack) -> CGFloat {
        let baseHeight = effectiveTrackHeight
        // TODO: Re-enable height expansion when we implement automation lanes (not just controls)
        // For now, keep same height since we're only showing automation controls in header
        return baseHeight
        // return track.automationExpanded ? baseHeight * automationExpandedMultiplier : baseHeight
    }
    
    /// Total height of all tracks (accounts for varying heights)
    private var totalTracksHeight: CGFloat {
        guard let tracks = project?.tracks else { return 0 }
        return tracks.reduce(0) { $0 + heightForTrack($1) }
    }
    
    // MARK: - Beat-Based Timeline (proper DAW architecture)
    // All timeline positions are in BEATS, not seconds. Conversion to seconds
    // only happens at the AVAudioEngine boundary.
    private var pixelsPerBeat: CGFloat { 40 * CGFloat(horizontalZoom) }
    
    // Project tempo for conversions at audio engine boundary
    private var projectTempo: Double { projectManager.currentProject?.tempo ?? 120.0 }
    
    // Legacy compatibility - will be removed after full refactor
    private var pixelsPerSecond: CGFloat {
        // Convert pixelsPerBeat to pixelsPerSecond using tempo
        // beatsPerSecond = tempo / 60
        pixelsPerBeat * CGFloat(projectTempo / 60.0)
    }
    
    // Unique ID for forcing view refresh when zoom changes
    private var zoomId: String {
        "\(horizontalZoom)-\(verticalZoom)"
    }
    
    // [V2-MULTISELECT] Marquee selection state
    @State private var marqueeStart: CGPoint? = nil
    
    // Content sizing for scroll sync
    private var contentSize: CGSize {
        guard let project = project else {
            return CGSize(width: 3000, height: 1000) // Default size
        }
        
        // Calculate total duration to display
        // Ensure at least 5 minutes (300s) of scrollable timeline,
        // or the actual project duration plus 30s padding, whichever is greater.
        let minDuration: TimeInterval = 300.0
        let tempo = project.tempo
        let displayDuration = max(minDuration, project.durationSeconds(tempo: tempo) + 30.0)
        
        let width = CGFloat(displayDuration) * pixelsPerSecond
        // Use totalTracksHeight to account for automation-expanded tracks being taller
        let height = totalTracksHeight
        return CGSize(width: width, height: height)
    }
    
    // [V2-MULTISELECT] Marquee drag gesture
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .modifiers(.command) // Cmd+drag for marquee
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    selection.isMarqueeActive = true
                }
                let origin = marqueeStart!
                let rect = CGRect(
                    x: min(origin.x, value.location.x),
                    y: min(origin.y, value.location.y),
                    width: abs(value.location.x - origin.x),
                    height: abs(value.location.y - origin.y)
                )
                selection.marqueeRect = rect
            }
            .onEnded { _ in
                defer {
                    selection.isMarqueeActive = false
                    selection.marqueeRect = .zero
                    marqueeStart = nil
                }
                // Hit-test regions (position in beats, duration in seconds)
                let ids = (project?.tracks ?? []).flatMap { track -> [UUID] in
                    track.regions.compactMap { region in
                        let frame = CGRect(
                            x: region.startBeat * pixelsPerBeat,
                            y: CGFloat(indexOfTrack(track)) * effectiveTrackHeight + CGFloat(8),
                            width: region.durationBeats * pixelsPerBeat,
                            height: effectiveTrackHeight - 16
                        )
                        return frame.intersects(selection.marqueeRect) ? region.id : nil
                    }
                }
                selection.selectedRegionIds.formUnion(ids)
                if selection.selectionAnchor == nil {
                    selection.selectionAnchor = selection.selectedRegionIds.first
                }
            }
    }
    
    // [V2-MULTISELECT] Helper to find track index
    private func indexOfTrack(_ track: AudioTrack) -> Int {
        (project?.tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
    }
    
    var body: some View {
        // [V2-ANALYSIS] Real TimelineActions wired to analysis + audio engine
        let actions = TimelineActions(
            matchTempoToRegion: { targetRegionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Helpers (local to keep change atomic)
                    func findRegion(_ id: UUID) -> (trackIndex: Int, regionIndex: Int)? {
                        for ti in project.tracks.indices {
                            if let ri = project.tracks[ti].regions.firstIndex(where: { $0.id == id }) {
                                return (ti, ri)
                            }
                        }
                        return nil
                    }
                    @MainActor func applyTempoRate(to regionId: UUID, rate: Float) {
                        guard let project = projectManager.currentProject else { return }
                        for track in project.tracks {
                            if track.regions.contains(where: { $0.id == regionId }),
                               let node = audioEngine.getTrackNode(for: track.id) {
                                node.setPlaybackRate(rate)    // AVAudioUnitTimePitch.rate
                                return
                            }
                        }
                    }
                    
                    // Target region + tempo
                    guard let (tTi, tRi) = findRegion(targetRegionId) else {
                        return
                    }
                    guard let currentProj = projectManager.currentProject,
                          tTi < currentProj.tracks.count,
                          tRi < currentProj.tracks[tTi].regions.count else { return }
                    let targetRegion = currentProj.tracks[tTi].regions[tRi]
                    let targetTempo = await analysisService.detectTempo(targetRegion.audioFile) // BPM
                    guard let targetTempo else {
                        return
                    }
                    projectManager.currentProject?.tracks[tTi].regions[tRi].detectedTempo = targetTempo
                    projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                    
                    // Other selected regions → detect → compute rate → write model → apply to node
                    let others = selection.selectedRegionIds.subtracting([targetRegionId])
                    for regionId in others {
                        guard let (ti, ri) = findRegion(regionId) else { continue }
                        guard let proj = projectManager.currentProject,
                              ti < proj.tracks.count,
                              ri < proj.tracks[ti].regions.count else { continue }
                        let r = proj.tracks[ti].regions[ri]
                        
                        let regionTempo = await analysisService.detectTempo(r.audioFile)
                        projectManager.currentProject?.tracks[ti].regions[ri].detectedTempo = regionTempo
                        
                        let rate: Float
                        if let regionTempo {
                            rate = Float(targetTempo / regionTempo)
                        } else {
                            rate = 1.0
                        }
                        
                        // Update model + engine
                        projectManager.currentProject?.tracks[ti].regions[ri].tempoRate = rate
                        await applyTempoRate(to: regionId, rate: rate)
                    }
                    
                    projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                }
            },
            
            matchPitchToRegion: { targetRegionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Helpers
                    func findRegion(_ id: UUID) -> (trackIndex: Int, regionIndex: Int)? {
                        for ti in project.tracks.indices {
                            if let ri = project.tracks[ti].regions.firstIndex(where: { $0.id == id }) {
                                return (ti, ri)
                            }
                        }
                        return nil
                    }
                    @MainActor func applyPitch(to regionId: UUID, cents: Float) {
                        guard let project = projectManager.currentProject else { return }
                        for track in project.tracks {
                            if track.regions.contains(where: { $0.id == regionId }),
                               let node = audioEngine.getTrackNode(for: track.id) {
                                node.setPitchShift(cents)      // AVAudioUnitTimePitch.pitch (in semitones; we convert inside)
                                return
                            }
                        }
                    }
                    func cents(from sourceKey: String, to targetKey: String) -> Float {
                        // simple, same as existing helper elsewhere
                        let order = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
                        let s = String(sourceKey.prefix(while: { $0 != " " })) // root
                        let t = String(targetKey.prefix(while: { $0 != " " }))
                        guard let si = order.firstIndex(of: s), let ti = order.firstIndex(of: t) else { return 0 }
                        var st = ti - si
                        if st > 6 { st -= 12 }
                        if st < -6 { st += 12 }
                        return Float(st * 100)
                    }
                    
                    // Target region + key
                    guard let (tTi, tRi) = findRegion(targetRegionId) else {
                        return
                    }
                    guard let currentProj2 = projectManager.currentProject,
                          tTi < currentProj2.tracks.count,
                          tRi < currentProj2.tracks[tTi].regions.count else { return }
                    let targetRegion2 = currentProj2.tracks[tTi].regions[tRi]
                    guard let targetKey = await analysisService.detectKey(targetRegion2.audioFile) else {
                        return
                    }
                    projectManager.currentProject?.tracks[tTi].regions[tRi].detectedKey = targetKey
                    projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                    
                    // Others → detect → compute cents → write + apply
                    let others = selection.selectedRegionIds.subtracting([targetRegionId])
                    for regionId in others {
                        guard let (ti, ri) = findRegion(regionId) else { continue }
                        guard let proj2 = projectManager.currentProject,
                              ti < proj2.tracks.count,
                              ri < proj2.tracks[ti].regions.count else { continue }
                        let r = proj2.tracks[ti].regions[ri]
                        
                        let regionKey = await analysisService.detectKey(r.audioFile)
                        projectManager.currentProject?.tracks[ti].regions[ri].detectedKey = regionKey
                        
                        let shiftCents: Float
                        if let regionKey {
                            shiftCents = cents(from: regionKey, to: targetKey)
                        } else {
                            shiftCents = 0
                        }
                        
                        projectManager.currentProject?.tracks[ti].regions[ri].pitchShiftCents = shiftCents
                        await applyPitch(to: regionId, cents: shiftCents)
                    }
                    
                    projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                }
            },
            
            autoMatchSelectedRegions: {
                Task { @MainActor in
                    guard projectManager.currentProject != nil else { return }
                    guard let anchor = selection.selectionAnchor else {
                        return
                    }
                    
                    // Count total regions to process (including anchor for analysis)
                    let totalRegions = selection.selectedRegionIds.count
                    
                    // Show HUD for batch operation
                    batchAnalysisState.start(regionCount: totalRegions)
                    showAnalysisHUD = true
                    
                    var completed = 0
                    
                    // Simple, deterministic behavior: use the first-selected (anchor) as the target
                    
                    // We can't reference 'actions' here due to capture order, so we'll duplicate the logic
                    // This is a temporary solution - in a real implementation we'd restructure this differently
                    
                    // First do tempo matching (inline implementation)
                    guard let project = projectManager.currentProject else { 
                        showAnalysisHUD = false
                        batchAnalysisState.reset()
                        return 
                    }
                    
                    // Helpers (local to keep change atomic)
                    func findRegion(_ id: UUID) -> (trackIndex: Int, regionIndex: Int)? {
                        for ti in project.tracks.indices {
                            if let ri = project.tracks[ti].regions.firstIndex(where: { $0.id == id }) {
                                return (ti, ri)
                            }
                        }
                        return nil
                    }
                    @MainActor func applyTempoRate(to regionId: UUID, rate: Float) {
                        guard let project = projectManager.currentProject else { return }
                        for track in project.tracks {
                            if track.regions.contains(where: { $0.id == regionId }),
                               let node = audioEngine.getTrackNode(for: track.id) {
                                node.setPlaybackRate(rate)    // AVAudioUnitTimePitch.rate
                                return
                            }
                        }
                    }
                    @MainActor func applyPitch(to regionId: UUID, cents: Float) {
                        guard let project = projectManager.currentProject else { return }
                        for track in project.tracks {
                            if track.regions.contains(where: { $0.id == regionId }),
                               let node = audioEngine.getTrackNode(for: track.id) {
                                node.setPitchShift(cents)      // AVAudioUnitTimePitch.pitch (in semitones; we convert inside)
                                return
                            }
                        }
                    }
                    func cents(from sourceKey: String, to targetKey: String) -> Float {
                        // simple, same as existing helper elsewhere
                        let order = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
                        let s = String(sourceKey.prefix(while: { $0 != " " })) // root
                        let t = String(targetKey.prefix(while: { $0 != " " }))
                        guard let si = order.firstIndex(of: s), let ti = order.firstIndex(of: t) else { return 0 }
                        var st = ti - si
                        if st > 6 { st -= 12 }
                        if st < -6 { st += 12 }
                        return Float(st * 100)
                    }
                    
                    // TEMPO MATCHING
                    guard let (tTi, tRi) = findRegion(anchor) else {
                        showAnalysisHUD = false
                        batchAnalysisState.reset()
                        return
                    }
                    guard let currentProj = projectManager.currentProject,
                          tTi < currentProj.tracks.count,
                          tRi < currentProj.tracks[tTi].regions.count else {
                        showAnalysisHUD = false
                        batchAnalysisState.reset()
                        return
                    }
                    let targetRegion = currentProj.tracks[tTi].regions[tRi]
                    let targetTempo = await analysisService.detectTempo(targetRegion.audioFile) // BPM
                    
                    // Update progress for anchor analysis
                    completed += 1
                    batchAnalysisState.updateProgress(completed: completed)
                    
                    guard let targetTempo else {
                        showAnalysisHUD = false
                        batchAnalysisState.reset()
                        return
                    }
                    projectManager.currentProject?.tracks[tTi].regions[tRi].detectedTempo = targetTempo
                    
                    // Other selected regions → detect → compute rate → write model → apply to node
                    let others = selection.selectedRegionIds.subtracting([anchor])
                    for regionId in others {
                        guard let (ti, ri) = findRegion(regionId) else { continue }
                        guard let proj = projectManager.currentProject,
                              ti < proj.tracks.count,
                              ri < proj.tracks[ti].regions.count else { continue }
                        let r = proj.tracks[ti].regions[ri]
                        
                        let regionTempo = await analysisService.detectTempo(r.audioFile)
                        projectManager.currentProject?.tracks[ti].regions[ri].detectedTempo = regionTempo
                        
                        // Update progress after analyzing each region
                        completed += 1
                        batchAnalysisState.updateProgress(completed: completed)
                        
                        let rate: Float
                        if let regionTempo {
                            rate = Float(targetTempo / regionTempo)
                        } else {
                            rate = 1.0
                        }
                        
                        // Update model + engine
                        projectManager.currentProject?.tracks[ti].regions[ri].tempoRate = rate
                        await applyTempoRate(to: regionId, rate: rate)
                    }
                    
                    // PITCH MATCHING
                    guard let projForPitch = projectManager.currentProject,
                          tTi < projForPitch.tracks.count,
                          tRi < projForPitch.tracks[tTi].regions.count else { return }
                    let targetRegionForPitch = projForPitch.tracks[tTi].regions[tRi]
                    guard let targetKey = await analysisService.detectKey(targetRegionForPitch.audioFile) else {
                        return
                    }
                    projectManager.currentProject?.tracks[tTi].regions[tRi].detectedKey = targetKey
                    
                    // Others → detect → compute cents → write + apply
                    for regionId in others {
                        guard let (ti, ri) = findRegion(regionId) else { continue }
                        guard let proj2 = projectManager.currentProject,
                              ti < proj2.tracks.count,
                              ri < proj2.tracks[ti].regions.count else { continue }
                        let r = proj2.tracks[ti].regions[ri]
                        
                        let regionKey = await analysisService.detectKey(r.audioFile)
                        projectManager.currentProject?.tracks[ti].regions[ri].detectedKey = regionKey
                        
                        let shiftCents: Float
                        if let regionKey {
                            shiftCents = cents(from: regionKey, to: targetKey)
                        } else {
                            shiftCents = 0
                        }
                        
                        projectManager.currentProject?.tracks[ti].regions[ri].pitchShiftCents = shiftCents
                        await applyPitch(to: regionId, cents: shiftCents)
                    }
                    
                    projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                    
                    // Hide HUD after completion with 0.5s delay
                    try? await Task.sleep(for: .milliseconds(500))
                    showAnalysisHUD = false
                    batchAnalysisState.reset()
                }
            },
            
            // 🎵 Audio Analysis Actions
            analyzeRegion: { regionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Show HUD for explicit analysis
                    batchAnalysisState.start(regionCount: 1)
                    showAnalysisHUD = true
                    
                    // Find the region
                    for track in project.tracks {
                        if let region = track.regions.first(where: { $0.id == regionId }) {
                            
                            // Perform analysis using the new unified API
                            let result = await analysisService.analyzeRegion(region)
                            
                            // Update the region with results
                            if let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }),
                               let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedTempo = result.tempo
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedKey = result.key
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].tempoConfidence = result.tempoConfidence
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].keyConfidence = result.keyConfidence
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedBeatTimesInSeconds = result.beats
                                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].downbeatIndices = result.downbeatIndices
                                
                                if let tempo = result.tempo {
                                    let conf = result.tempoConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "N/A"
                                }
                                if let key = result.key {
                                    let conf = result.keyConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "N/A"
                                }
                                if let beats = result.beats {
                                }
                                
                                projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
                            }
                            
                            // Update HUD to complete
                            batchAnalysisState.updateProgress(completed: 1)
                            
                            // Hide HUD after 0.5s delay
                            try? await Task.sleep(for: .milliseconds(500))
                            showAnalysisHUD = false
                            batchAnalysisState.reset()
                            
                            return
                        }
                    }
                    
                    // If region not found, hide HUD immediately
                    showAnalysisHUD = false
                    batchAnalysisState.reset()
                }
            },
            
            // 🎧 Audio Export Actions
            exportOriginalAudio: { regionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Find the region
                    for track in project.tracks {
                        if let region = track.regions.first(where: { $0.id == regionId }) {
                            do {
                                let exportURL = try await exportService.exportOriginal(region.audioFile, regionId: regionId)
                                exportService.revealExportDirectory()
                            } catch {
                            }
                            return
                        }
                    }
                }
            },
            
            exportProcessedAudio: { regionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Find the region and its processing settings
                    for track in project.tracks {
                        if let region = track.regions.first(where: { $0.id == regionId }) {
                            do {
                                let exportURL = try await exportService.exportProcessed(
                                    region.audioFile,
                                    regionId: regionId,
                                    tempoRate: region.tempoRate,
                                    pitchShiftCents: region.pitchShiftCents
                                )
                                exportService.revealExportDirectory()
                            } catch {
                            }
                            return
                        }
                    }
                }
            },
            
            exportAudioComparison: { regionId in
                Task { @MainActor in
                    guard let project = projectManager.currentProject else { return }
                    
                    // Find the region and export both versions
                    for track in project.tracks {
                        if let region = track.regions.first(where: { $0.id == regionId }) {
                            do {
                                let (originalURL, processedURL) = try await exportService.exportComparison(
                                    region.audioFile,
                                    regionId: regionId,
                                    tempoRate: region.tempoRate,
                                    pitchShiftCents: region.pitchShiftCents
                                )
                                exportService.revealExportDirectory()
                            } catch {
                            }
                            return
                        }
                    }
                }
            }
        )
        
        ZStack(alignment: .top) {
            // Main timeline content
            VStack(spacing: 0) {
                if project != nil {
                    HStack(spacing: 0) {
                        // LEFT: Track Headers Column (vertical scrolling only)
                        VStack(spacing: 0) {
                            // Header with Add Track button and Zoom Controls
                            HStack(spacing: 0) {
                                // Professional Add Track button with hover states
                                Button(action: onAddTrack) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(AddTrackButtonStyle())
                                .frame(width: 32, height: rulerHeight)
                                .help("Add Track (⇧⌘N)")
                                
                                // Snap to Grid Toggle
                                Button(action: { snapToGrid.toggle() }) {
                                    Image(systemName: snapToGrid ? "circle.grid.cross.fill" : "circle.grid.cross")
                                        .foregroundColor(snapToGrid ? .blue : .secondary)
                                        .font(.system(size: 12, weight: snapToGrid ? .semibold : .regular))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28, height: rulerHeight)
                                .help(snapToGrid ? "Disable Snap to Grid (⌘G)" : "Enable Snap to Grid (⌘G)")
                                
                                // Horizontal zoom control (compact)
                                HStack(spacing: 2) {
                                    Image(systemName: "minus.magnifyingglass")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 9))
                                    
                                    Slider(value: $horizontalZoom, in: 0.1...10.0, step: 0.1)
                                        .controlSize(.mini)
                                        .frame(width: 60)
                                    
                                    Image(systemName: "plus.magnifyingglass")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 9))
                                    
                                    Text("\(String(format: "%.1f", horizontalZoom))x")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .frame(width: 26, alignment: .leading)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 4)
                                .frame(height: rulerHeight)
                                .help("Horizontal Zoom")
                                
                                // Vertical zoom control (compact)
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.and.down.text.horizontal")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 9))
                                    
                                    Slider(value: $verticalZoom, in: 0.5...3.0, step: 0.1)
                                        .controlSize(.mini)
                                        .frame(width: 50)
                                    
                                    Text("\(String(format: "%.1f", verticalZoom))x")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .frame(width: 26, alignment: .leading)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 4)
                                .frame(height: rulerHeight)
                                .help("Vertical Zoom")
                                
                                // Remaining header space
                                Rectangle()
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .frame(height: rulerHeight)
                            }
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                                alignment: .bottom
                            )
                            
                            // Synchronized track headers
                            SynchronizedScrollView(
                                axes: .vertical,
                                showsIndicators: false,
                                contentSize: CGSize(width: headerWidth, height: contentSize.height),
                                offsetX: .constant(0),
                                offsetY: $scrollSync.verticalScrollOffset,
                                isUpdatingX: { false },
                                isUpdatingY: { scrollSync.isUpdatingVertical },
                                onUserScrollX: { _ in },
                                onUserScrollY: { scrollSync.updateVerticalOffset($0) }
                            ) {
                                AnyView(trackHeadersContent)
                            }
                            .id("headers-\(zoomId)")  // Force refresh on zoom change
                        }
                        .frame(width: headerWidth)
                        
                        // Vertical separator
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 1)
                        
                        // RIGHT: Timeline Ruler + Tracks Area
                        VStack(spacing: 0) {
                            // Timeline ruler (horizontal scrolling only)
                            SynchronizedScrollView(
                                axes: .horizontal,
                                showsIndicators: false,
                                contentSize: CGSize(width: contentSize.width, height: rulerHeight),
                                offsetX: $scrollSync.horizontalScrollOffset,
                                offsetY: .constant(0),
                                isUpdatingX: { scrollSync.isUpdatingHorizontal },
                                isUpdatingY: { false },
                                onUserScrollX: { scrollSync.updateHorizontalOffset($0) },
                                onUserScrollY: { _ in }
                            ) {
                                AnyView(timelineRulerContent)
                            }
                            .frame(height: rulerHeight)
                            .id("ruler-\(zoomId)")  // Force refresh on zoom change
                            
                            // Horizontal separator
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            
                            // Tracks area (both axes - master scroll view)
                            SynchronizedScrollView(
                                axes: .both,
                                showsIndicators: false,
                                contentSize: contentSize,
                                offsetX: $scrollSync.horizontalScrollOffset,
                                offsetY: $scrollSync.verticalScrollOffset,
                                isUpdatingX: { scrollSync.isUpdatingHorizontal },
                                isUpdatingY: { scrollSync.isUpdatingVertical },
                                onUserScrollX: { scrollSync.updateHorizontalOffset($0) },
                                onUserScrollY: { scrollSync.updateVerticalOffset($0) }
                            ) {
                                AnyView(tracksAreaContent)
                            }
                            .id("tracks-\(zoomId)")  // Force refresh on zoom change
                        }
                        .coordinateSpace(name: "timelineRoot")
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                } else {
                    EmptyTimelineView(
                        onCreateProject: onCreateProject,
                        onOpenProject: onOpenProject,
                        projectManager: projectManager
                    )
                }
            }
            .frame(minHeight: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // [V2-MULTISELECT] Selection count badge - ISOLATED VIEW to prevent cascade re-renders
            SelectionCountBadge(selection: selection)
            
            // 🎛️ Floating Analysis HUD (macOS-style)
            analysisHUD
        }
        .environment(\.timelineActions, actions) // [V2-ANALYSIS] Provide actions to all child views
        .sheet(isPresented: $showingTokenizeSheet) {
            TokenizeComingSoonView()
        }
        .sheet(isPresented: $showingWalletConnection) {
            WalletComingSoonView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenizeProject)) { _ in
            showingTokenizeSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWalletConnection)) { _ in
            showingWalletConnection = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMarketplace)) { _ in
            // Navigate to marketplace tab in the inspector
            NotificationCenter.default.post(name: .openVisualTab, object: nil)
        }
        .modifier(TimelineEditingNotifications(
            onSplit: splitSelectedRegionsAtPlayhead,
            onJoin: joinSelectedRegions,
            onTrimStart: trimSelectedRegionsStart,
            onTrimEnd: trimSelectedRegionsEnd,
            onNudgeLeft: { nudgeSelectedRegions(byBars: -1) },
            onNudgeRight: { nudgeSelectedRegions(byBars: 1) },
            onSelectNext: { selectAdjacentRegion(next: true) },
            onSelectPrevious: { selectAdjacentRegion(next: false) },
            onSelectAbove: { selectRegionOnAdjacentTrack(above: true) },
            onSelectBelow: { selectRegionOnAdjacentTrack(above: false) },
            onCreateCrossfade: createCrossfadeForSelectedRegions
        ))
        .modifier(TimelineNavigationNotifications(
            onZoomToSelection: zoomToSelection,
            onGoToNextRegion: goToNextRegion,
            onGoToPreviousRegion: goToPreviousRegion,
            onMoveBeatForward: { movePlayhead(byBeats: 1) },
            onMoveBeatBackward: { movePlayhead(byBeats: -1) },
            onMoveBarForward: { movePlayhead(byBars: 1) },
            onMoveBarBackward: { movePlayhead(byBars: -1) }
        ))
        // Selection observer isolated to prevent cascade re-renders
        .background {
            AudioSelectionObserver(
                selection: selection,
                selectedRegionId: $selectedRegionId
            )
        }
        .onChange(of: projectManager.currentProject?.id) { _, _ in
            // Clear selection when switching to a new project
            selection.clearAll()
        }
        // MARK: - Catch Playhead Observer (Isolated for Performance)
        // CRITICAL: Using a separate view prevents audioEngine.currentPosition from being
        // tracked as a dependency of IntegratedTimelineView, avoiding full re-renders
        .background {
            CatchPlayheadObserver(
                audioEngine: audioEngine,
                catchPlayheadEnabled: catchPlayheadEnabled,
                onCatchPlayhead: { currentBeat in
                    catchPlayheadIfNeeded(currentBeat: currentBeat)
                }
            )
        }
    }
    
    // MARK: - Catch Playhead Logic
    
    /// Scrolls the timeline view to keep the playhead visible when playing
    /// Professional DAW style: playhead stays visible, view scrolls to follow
    private func catchPlayheadIfNeeded(currentBeat: Double) {
        guard project != nil else { return }
        
        // Playhead position in pixels from beats (beats are source of truth)
        let playheadX = CGFloat(currentBeat) * pixelsPerBeat
        
        // Current scroll offset (absolute pixels)
        let currentScrollOffset = scrollSync.horizontalScrollOffset
        
        // Estimate visible width (use a reasonable estimate based on typical screen sizes)
        // At 1x zoom with pixelsPerSecond = 100, a 1200px wide view shows 12 seconds
        let estimatedVisibleWidth: CGFloat = 1200.0
        
        // Calculate the visible window in content coordinates
        let windowStart = currentScrollOffset
        let windowEnd = currentScrollOffset + estimatedVisibleWidth
        
        // Margin before we scroll (10% of visible area = 120 pixels)
        let margin: CGFloat = estimatedVisibleWidth * 0.1
        
        // Check if playhead is approaching right edge
        if playheadX > (windowEnd - margin) && playheadX < contentSize.width {
            // Scroll to put playhead at 30% from left edge
            let targetScrollOffset = playheadX - (estimatedVisibleWidth * 0.3)
            let clampedOffset = max(0, min(contentSize.width - estimatedVisibleWidth, targetScrollOffset))
            
            scrollSync.updateHorizontalOffset(clampedOffset)
        }
        
        // Check if playhead went backwards (loop or seek)
        if playheadX < windowStart {
            // Scroll back to show playhead at 30% from left
            let targetScrollOffset = max(0, playheadX - (estimatedVisibleWidth * 0.3))
            
            scrollSync.updateHorizontalOffset(targetScrollOffset)
        }
    }
    
    // MARK: - Batch Analysis HUD
    
    /// Floating macOS-style HUD for batch audio analysis operations.
    /// Appears centered in the window with a dimmed backdrop.
    private var analysisHUD: some View {
        Group {
            if showAnalysisHUD {
                ZStack {
                    // Dimmed backdrop (non-blocking)
                    Color.black.opacity(0.20)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    
                    // HUD Box
                    VStack(spacing: 8) {
                        Text(batchAnalysisState.title)
                            .font(.system(size: 13, weight: .semibold))
                        
                        if !batchAnalysisState.subtitle.isEmpty {
                            Text(batchAnalysisState.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        ProgressView(value: batchAnalysisState.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 220)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    )
                    .allowsHitTesting(true) // HUD box captures clicks
                }
                .animation(.easeInOut(duration: 0.20), value: showAnalysisHUD)
            }
        }
    }
    
    // MARK: - Content Views
    
    private var trackHeadersContent: some View {
        HStack(spacing: 0) {
            // Small leading padding to prevent track numbers from being clipped at left edge
            Spacer(minLength: 0)
                .frame(width: 3)
            
            LazyVStack(spacing: 0) {
                ForEach(project?.tracks ?? []) { audioTrack in
                IntegratedTrackHeader(
                    trackId: audioTrack.id,
                    selectedTrackId: $selectedTrackId,
                    selectedTrackIds: $selectedTrackIds,
                    height: heightForTrack(audioTrack),  // Per-track height
                    audioEngine: audioEngine,
                    projectManager: projectManager,
                    onSelect: { modifiers in
                        onSelectTrack(audioTrack.id, modifiers)
                    },
                    onDelete: {
                        onDeleteTracks()
                    },
                    onRename: { newName in
                        onRenameTrack(newName)
                    },
                    onNewAudioTrack: {
                        onNewAudioTrack()
                    },
                    onNewMIDITrack: {
                        onNewMIDITrack()
                    },
                    onMoveTrack: { sourceIndex, destIndex in
                        projectManager.moveTrack(from: sourceIndex, to: destIndex)
                        // Update audio engine with new track order
                        if let project = projectManager.currentProject {
                            audioEngine.updateProjectData(project)
                        }
                    }
                )
                .id("\(audioTrack.id)-\(selectedTrackId?.uuidString ?? "none")-\(audioTrack.automationExpanded)")
            }
            }  // Close LazyVStack
            
            // Small trailing padding for balance
            Spacer(minLength: 0)
                .frame(width: 3)
        }  // Close HStack
        .frame(width: headerWidth)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var timelineRulerContent: some View {
        let projectTempo = projectManager.currentProject?.tempo ?? 120.0
        
        return ProfessionalTimelineRuler(
            pixelsPerBeat: pixelsPerBeat,
            contentWidth: contentSize.width,
            height: rulerHeight,  // keep at 60
            projectTempo: projectTempo,
            snapToGrid: snapToGrid,  // [PHASE-1] Pass snap setting for cycle region
            // PERFORMANCE: Pass cycle state as parameters to avoid ruler observing audioEngine
            isCycleEnabled: audioEngine.isCycleEnabled,
            cycleStartBeat: audioEngine.cycleStartBeat,
            cycleEndBeat: audioEngine.cycleEndBeat,
            onSeek: { beat in audioEngine.seek(toBeat: beat) },
            onCycleRegionChanged: { start, end in audioEngine.setCycleRegion(startBeat: start, endBeat: end) }
        )
        .frame(width: contentSize.width, height: rulerHeight)
    }
    
    // [PHASE-8] Helper to build track row - extracted to help type checker
    private func trackRowView(for audioTrack: AudioTrack) -> some View {
        IntegratedTrackRow(
            audioTrack: audioTrack,
            selectedTrackId: $selectedTrackId,
            selection: selection,
            height: heightForTrack(audioTrack),
            pixelsPerBeat: pixelsPerBeat,
            audioEngine: audioEngine,
            projectManager: projectManager,
            snapToGrid: snapToGrid,
            timeDisplayMode: timeDisplayMode,
            onSelect: {
                selectedTrackId = audioTrack.id
            },
            onRegionMove: moveRegion,
            onRegionMoveToTrack: moveRegionToTrack,
            onMIDIRegionDoubleClick: { midiRegion, track in
                onOpenPianoRoll?(midiRegion, track)
            },
            onMIDIRegionBounce: { midiRegion, track in
                onBounceMIDIRegion?(midiRegion, track)
            },
            onMIDIRegionDelete: { midiRegion, track in
                onDeleteMIDIRegion?(midiRegion, track)
            },
            scrollOffset: scrollSync.horizontalScrollOffset,
            viewportWidth: viewportWidth
        )
        .id("\(audioTrack.id)-row-\(selectedTrackId?.uuidString ?? "none")-\(audioTrack.automationExpanded)")
    }
    
    private var tracksAreaContent: some View {
        ZStack(alignment: .topLeading) {
            // Background grid
            IntegratedGridBackground(
                contentSize: contentSize,
                trackHeight: effectiveTrackHeight,
                pixelsPerBeat: pixelsPerBeat,
                trackCount: project?.tracks.count ?? 0
            )
            
            // Track rows with regions (automation curves are now overlays inside each row)
            LazyVStack(spacing: 0) {
                ForEach(project?.tracks ?? []) { audioTrack in
                    trackRowView(for: audioTrack)
                }
            }
            
            // [V2-MULTISELECT] Marquee selection overlay - ISOLATED to prevent invalidating parent
            MarqueeOverlay(selection: selection)
            
            // Full-height playhead extending through all tracks
            // PERFORMANCE: Uses @Observable TransportModel for fine-grained updates
            TimelinePlayhead(
                height: contentSize.height,
                pixelsPerBeat: pixelsPerBeat
            )
            
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background(Color(NSColor.textBackgroundColor))
        .contentShape(Rectangle())
        .gesture(marqueeGesture)
        .environment(projectManager)  // Inject for TimelinePlayhead
        .onReceive(NotificationCenter.default.publisher(for: .init("SelectAllRegions"))) { _ in
            // [V2-MULTISELECT] Select All
            let allIds = (project?.tracks.flatMap { $0.regions.map(\.id) } ?? [])
            selection.selectAll(allIds)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearSelection"))) { _ in
            // [V2-MULTISELECT] Clear Selection
            selection.clear()
        }
        .onDrop(of: [.wav], isTargeted: $isDragOver) { providers, location in
            return handleFileDrop(providers: providers, location: location)
        }
        .overlay(
            // Visual feedback during drag-over
            isDragOver ? 
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.green, lineWidth: 3, antialiased: true)
                    .background(
                        Color.green.opacity(0.1)
                    )
                    .overlay(
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("Drop audio file here")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                    )
                : nil
        )
    }
    
    // MARK: - Create Crossfade (⌘⌥X)
    
    /// Create a crossfade between two selected adjacent regions
    private func createCrossfadeForSelectedRegions() {
        guard var project = projectManager.currentProject else { return }
        
        let selectedIds = selection.selectedRegionIds
        guard selectedIds.count == 2 else { return } // Need exactly 2 regions
        
        // Find the regions and verify they're on the same track
        var foundRegions: [(region: AudioRegion, trackIndex: Int, regionIndex: Int)] = []
        
        for (trackIndex, track) in project.tracks.enumerated() {
            for (regionIndex, region) in track.regions.enumerated() {
                if selectedIds.contains(region.id) {
                    foundRegions.append((region, trackIndex, regionIndex))
                }
            }
        }
        
        guard foundRegions.count == 2,
              foundRegions[0].trackIndex == foundRegions[1].trackIndex else {
            return // Must be on same track
        }
        
        let trackIndex = foundRegions[0].trackIndex
        let tempo = project.tempo
        
        // Sort by start position
        foundRegions.sort { $0.region.startBeat < $1.region.startBeat }
        
        let firstRegion = foundRegions[0].region
        let secondRegion = foundRegions[1].region
        let firstRegionIndex = foundRegions[0].regionIndex
        let secondRegionIndex = foundRegions[1].regionIndex
        
        // Check if they're adjacent or overlapping
        let firstEndBeat = firstRegion.endBeat
        let gap = secondRegion.startBeat - firstEndBeat
        
        // Calculate crossfade duration (default: 0.1 seconds or overlap amount)
        let crossfadeDuration: TimeInterval
        if gap < 0 {
            // Overlapping - use overlap amount
            crossfadeDuration = abs(gap) * (60.0 / tempo)
        } else if gap < 1.0 { // Less than 1 beat gap
            // Adjacent - use 0.1 seconds
            crossfadeDuration = 0.1
        } else {
            // Too far apart - use 0.25 seconds
            crossfadeDuration = 0.25
        }
        
        // Apply fade out to first region and fade in to second region
        project.tracks[trackIndex].regions[firstRegionIndex].fadeOut = crossfadeDuration
        project.tracks[trackIndex].regions[secondRegionIndex].fadeIn = crossfadeDuration
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        audioEngine.loadProject(project)
    }
    
    // MARK: - Join Regions (⌘J)
    
    /// Join multiple selected regions on the same track into one
    private func joinSelectedRegions() {
        guard var project = projectManager.currentProject else { return }
        
        let selectedIds = selection.selectedRegionIds
        guard selectedIds.count >= 2 else { return }
        
        // Find which track contains the selected regions
        var targetTrackIndex: Int?
        var regionsToJoin: [AudioRegion] = []
        
        for (trackIndex, track) in project.tracks.enumerated() {
            let trackRegions = track.regions.filter { selectedIds.contains($0.id) }
            if !trackRegions.isEmpty {
                if targetTrackIndex != nil {
                    // Regions on multiple tracks - can't join
                    return
                }
                targetTrackIndex = trackIndex
                regionsToJoin = trackRegions
            }
        }
        
        guard let trackIndex = targetTrackIndex, regionsToJoin.count >= 2 else { return }
        
        // Sort by start position
        regionsToJoin.sort { $0.startBeat < $1.startBeat }
        
        // Check if all regions use the same audio file (simple join case)
        let firstFile = regionsToJoin.first?.audioFile.storedPath
        let allSameFile = regionsToJoin.allSatisfy { $0.audioFile.storedPath == firstFile }
        
        if allSameFile {
            // Simple join: extend the first region to cover all
            guard let firstRegion = regionsToJoin.first,
                  let lastRegion = regionsToJoin.last else { return }
            let tempo = project.tempo
            
            // Calculate new duration
            let newEndBeat = lastRegion.endBeat
            let newDurationBeats = newEndBeat - firstRegion.startBeat
            
            // Create joined region
            var joinedRegion = firstRegion
            joinedRegion.durationBeats = newDurationBeats
            joinedRegion.fadeOut = lastRegion.fadeOut // Keep the last region's fade out
            
            // Remove all selected regions and add the joined one
            project.tracks[trackIndex].regions.removeAll { selectedIds.contains($0.id) }
            project.tracks[trackIndex].addRegion(joinedRegion)
            
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            // Select the new joined region
            selection.selectOnly(joinedRegion.id)
            
            // Reload audio engine
            audioEngine.loadProject(project)
        }
        // TODO: For different source files, would need to bounce to new audio file
    }
    
    // MARK: - Trim to Playhead (⌘[ and ⌘])
    
    /// Trim the start of selected regions to the playhead position
    private func trimSelectedRegionsStart() {
        guard var project = projectManager.currentProject else { return }
        
        let playheadBeat = audioEngine.currentPosition.beats
        let tempo = project.tempo
        
        let selectedIds = selection.selectedRegionIds
        guard !selectedIds.isEmpty else { return }
        
        var modified = false
        
        for trackIndex in project.tracks.indices {
            for regionIndex in project.tracks[trackIndex].regions.indices {
                let region = project.tracks[trackIndex].regions[regionIndex]
                if selectedIds.contains(region.id) {
                    let regionEndBeat = region.endBeat
                    
                    // Only trim if playhead is inside the region
                    if playheadBeat > region.startBeat && playheadBeat < regionEndBeat {
                        // Calculate how much we're trimming from the start (all in beats)
                        let trimBeats = playheadBeat - region.startBeat
                        let trimSeconds = trimBeats * (60.0 / tempo)  // For audio offset (AV boundary)
                        
                        project.tracks[trackIndex].regions[regionIndex].startBeat = playheadBeat
                        project.tracks[trackIndex].regions[regionIndex].offset += trimSeconds
                        project.tracks[trackIndex].regions[regionIndex].durationBeats -= trimBeats
                        project.tracks[trackIndex].regions[regionIndex].fadeIn = 0 // Reset fade after trim
                        
                        modified = true
                    }
                }
            }
        }
        
        if modified {
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            audioEngine.loadProject(project)
        }
    }
    
    /// Trim the end of selected regions to the playhead position
    private func trimSelectedRegionsEnd() {
        guard var project = projectManager.currentProject else { return }
        
        let playheadBeat = audioEngine.currentPosition.beats
        
        let selectedIds = selection.selectedRegionIds
        guard !selectedIds.isEmpty else { return }
        
        var modified = false
        
        for trackIndex in project.tracks.indices {
            for regionIndex in project.tracks[trackIndex].regions.indices {
                let region = project.tracks[trackIndex].regions[regionIndex]
                if selectedIds.contains(region.id) {
                    let regionEndBeat = region.endBeat
                    
                    // Only trim if playhead is inside the region
                    if playheadBeat > region.startBeat && playheadBeat < regionEndBeat {
                        // Calculate new duration (in beats)
                        let newDurationBeats = playheadBeat - region.startBeat
                        
                        // Update region duration
                        project.tracks[trackIndex].regions[regionIndex].durationBeats = newDurationBeats
                        project.tracks[trackIndex].regions[regionIndex].fadeOut = 0 // Reset fade after trim
                        
                        modified = true
                    }
                }
            }
        }
        
        if modified {
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            audioEngine.loadProject(project)
        }
    }
    
    // MARK: - Tab to Next/Previous Region
    
    /// Select the next or previous region (by position)
    private func selectAdjacentRegion(next: Bool) {
        guard let project = projectManager.currentProject else { return }
        
        // Collect all audio regions with their track info, sorted by start position
        var allRegions: [(region: AudioRegion, trackId: UUID)] = []
        for track in project.tracks {
            for region in track.regions {
                allRegions.append((region, track.id))
            }
        }
        
        // Sort by start beat
        allRegions.sort { $0.region.startBeat < $1.region.startBeat }
        
        guard !allRegions.isEmpty else { return }
        
        // Find current selection
        let currentIds = selection.selectedRegionIds
        
        if currentIds.isEmpty {
            // Nothing selected - select first or last region
            if next {
                if let first = allRegions.first {
                    selection.selectOnly(first.region.id)
                }
                            } else {
                if let last = allRegions.last {
                    selection.selectOnly(last.region.id)
                }
            }
                    } else {
            // Find the index of the currently selected region (use anchor or first selected)
            let anchorId = selection.selectionAnchor ?? currentIds.first
            if let currentIndex = allRegions.firstIndex(where: { $0.region.id == anchorId }) {
                let newIndex: Int
                if next {
                    newIndex = (currentIndex + 1) % allRegions.count
                } else {
                    newIndex = (currentIndex - 1 + allRegions.count) % allRegions.count
                }
                selection.selectOnly(allRegions[newIndex].region.id)
            } else {
                // Current selection not found, select first/last
                if next {
                    if let first = allRegions.first {
                        selection.selectOnly(first.region.id)
                    }
                } else {
                    if let last = allRegions.last {
                        selection.selectOnly(last.region.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Select Region on Adjacent Track (↑/↓)
    
    /// Select a region on the track above or below
    private func selectRegionOnAdjacentTrack(above: Bool) {
        guard let project = projectManager.currentProject else { return }
        guard !project.tracks.isEmpty else { return }
        
        // Find current selection's track
        let currentIds = selection.selectedRegionIds
        var currentTrackIndex: Int?
        var currentBeat: Double = 0
        
        // Find the track and beat of the currently selected region
        for (trackIndex, track) in project.tracks.enumerated() {
            for region in track.regions {
                if currentIds.contains(region.id) {
                    currentTrackIndex = trackIndex
                    currentBeat = region.startBeat
                    break
                }
            }
            if currentTrackIndex != nil { break }
        }
        
        guard let trackIdx = currentTrackIndex else {
            // Nothing selected - select first region on first track
            if let firstTrack = project.tracks.first,
               let firstRegion = firstTrack.regions.first {
                selection.selectOnly(firstRegion.id)
            }
            return
        }
        
        // Calculate target track index
        let targetTrackIndex: Int
        if above {
            targetTrackIndex = (trackIdx - 1 + project.tracks.count) % project.tracks.count
        } else {
            targetTrackIndex = (trackIdx + 1) % project.tracks.count
        }
        
        let targetTrack = project.tracks[targetTrackIndex]
        
        // Find the region on target track closest to the current beat position
        if targetTrack.regions.isEmpty {
            // No regions on target track, keep current selection
            return
        }
        
        let closestRegion = targetTrack.regions.min { abs($0.startBeat - currentBeat) < abs($1.startBeat - currentBeat) }
        if let region = closestRegion {
            selection.selectOnly(region.id)
        }
    }
    
    // MARK: - Zoom to Selection (Z)
    
    /// Zoom to fit selected regions in view
    private func zoomToSelection() {
        guard let project = projectManager.currentProject else { return }
        
        let selectedIds = selection.selectedRegionIds
        guard !selectedIds.isEmpty else { return }
        
        // Find bounds of selected regions
        var minBeat: Double = .infinity
        var maxBeat: Double = -.infinity
        let tempo = project.tempo
        
        for track in project.tracks {
            for region in track.regions {
                if selectedIds.contains(region.id) {
                    minBeat = min(minBeat, region.startBeat)
                    maxBeat = max(maxBeat, region.endBeat)
                }
            }
        }
        
        guard minBeat < maxBeat else { return }
        
        // Add padding (2 beats on each side)
        let paddedMinBeat = max(0, minBeat - 2)
        let paddedMaxBeat = maxBeat + 2
        let durationBeats = paddedMaxBeat - paddedMinBeat
        
        // Calculate zoom to fit selection
        let screenWidth = NSScreen.main?.frame.width ?? 1400
        let estimatedViewportWidth = max(600, screenWidth - 700)
        let basePixelsPerBeat: Double = 40
        let calculatedZoom = estimatedViewportWidth / (durationBeats * basePixelsPerBeat)
        
        // Post zoom change through audioEngine or projectManager
        // Note: horizontalZoom is managed in MainDAWView, so we post a notification
        NotificationCenter.default.post(
            name: NSNotification.Name("SetHorizontalZoom"),
            object: nil,
            userInfo: ["zoom": min(10.0, max(0.1, calculatedZoom))]
        )
    }
    
    // MARK: - Go to Next/Previous Region (⌘⇧→/←)
    
    /// Move playhead to next region and select it
    private func goToNextRegion() {
        guard let project = projectManager.currentProject else { return }
        
        let currentBeat = audioEngine.currentPosition.beats
        let tempo = project.tempo
        
        // Collect all regions sorted by start beat
        var allRegions: [(region: AudioRegion, trackId: UUID)] = []
        for track in project.tracks {
            for region in track.regions {
                allRegions.append((region, track.id))
            }
        }
        allRegions.sort { $0.region.startBeat < $1.region.startBeat }
        
        // Find next region after current playhead
        if let nextRegion = allRegions.first(where: { $0.region.startBeat > currentBeat + 0.01 }) {
            // Move playhead to region start (in beats)
            audioEngine.seek(toBeat: nextRegion.region.startBeat)
            selection.selectOnly(nextRegion.region.id)
        } else if let firstRegion = allRegions.first {
            // Wrap to first region
            audioEngine.seek(toBeat: firstRegion.region.startBeat)
            selection.selectOnly(firstRegion.region.id)
        }
    }
    
    /// Move playhead to previous region and select it
    private func goToPreviousRegion() {
        guard let project = projectManager.currentProject else { return }
        
        let currentBeat = audioEngine.currentPosition.beats
        let tempo = project.tempo
        
        // Collect all regions sorted by start beat (descending)
        var allRegions: [(region: AudioRegion, trackId: UUID)] = []
        for track in project.tracks {
            for region in track.regions {
                allRegions.append((region, track.id))
            }
        }
        allRegions.sort { $0.region.startBeat > $1.region.startBeat }
        
        // Find previous region before current playhead
        if let prevRegion = allRegions.first(where: { $0.region.startBeat < currentBeat - 0.01 }) {
            audioEngine.seek(toBeat: prevRegion.region.startBeat)
            selection.selectOnly(prevRegion.region.id)
        } else if let lastRegion = allRegions.first {
            // Wrap to last region
            audioEngine.seek(toBeat: lastRegion.region.startBeat)
            selection.selectOnly(lastRegion.region.id)
        }
    }
    
    // MARK: - Beat/Bar Navigation (./,)
    
    /// Move playhead by the specified number of beats
    private func movePlayhead(byBeats beats: Int) {
        let currentBeat = audioEngine.currentPosition.beats
        let newBeat = max(0, currentBeat + Double(beats))
        audioEngine.seek(toBeat: newBeat)
    }
    
    /// Move playhead by the specified number of bars
    private func movePlayhead(byBars bars: Int) {
        guard let project = projectManager.currentProject else { return }
        let timeSignature = project.timeSignature
        let beatsPerBar = Double(timeSignature.numerator)
        let currentBeat = audioEngine.currentPosition.beats
        let newBeat = max(0, currentBeat + Double(bars) * beatsPerBar)
        audioEngine.seek(toBeat: newBeat)
    }
    
    // MARK: - Nudge Regions (⇧←/⇧→)
    
    /// Nudge all selected regions by the specified number of bars
    private func nudgeSelectedRegions(byBars bars: Int) {
        guard var project = projectManager.currentProject else { return }
        
        let timeSignature = project.timeSignature
        let beatsPerBar = Double(timeSignature.numerator)
        let nudgeAmount = Double(bars) * beatsPerBar
        
        // Get selected audio region IDs
        let selectedIds = selection.selectedRegionIds
        
        guard !selectedIds.isEmpty else { return }
        
        var modified = false
        
        // Nudge all selected audio regions
        for trackIndex in project.tracks.indices {
            for regionIndex in project.tracks[trackIndex].regions.indices {
                let region = project.tracks[trackIndex].regions[regionIndex]
                if selectedIds.contains(region.id) {
                    let newStartBeat = region.startBeat + nudgeAmount
                    // Don't allow negative start positions
                    if newStartBeat >= 0 {
                        project.tracks[trackIndex].regions[regionIndex].startBeat = newStartBeat
                        modified = true
                    }
                }
            }
        }
        
        if modified {
            project.modifiedAt = Date()
            projectManager.currentProject = project
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            audioEngine.loadProject(project)
        }
    }
    
    // MARK: - Split at Playhead (⌘T)
    
    /// Split all selected regions at the current playhead position
    private func splitSelectedRegionsAtPlayhead() {
        guard let project = projectManager.currentProject else { return }
        
        let playheadBeat = audioEngine.currentPosition.beats
        
        // Get selected audio region IDs
        let selectedIds = selection.selectedRegionIds
        
        // Also check for selected MIDI region
        let selectedMIDIId = selection.selectedMIDIRegionId
        
        var splitCount = 0
        
        // Split audio regions
        for track in project.tracks {
            for region in track.regions {
                // Check if this region is selected AND playhead is inside it
                if selectedIds.contains(region.id) {
                    let regionEndBeat = region.endBeat
                    if playheadBeat > region.startBeat && playheadBeat < regionEndBeat {
                        projectManager.splitRegionAtPosition(region.id, trackId: track.id, splitBeat: playheadBeat)
                        splitCount += 1
                    }
                }
            }
        }
        
        // TODO: Add MIDI region splitting when needed
        // For now, MIDI regions don't support splitting
        
        // If nothing was selected but playhead is inside a region, split that region
        if splitCount == 0 && selectedIds.isEmpty && selectedMIDIId == nil {
            // Find any region under the playhead and split it
        for track in project.tracks {
                for region in track.regions {
                    let regionEndBeat = region.endBeat
                    if playheadBeat > region.startBeat && playheadBeat < regionEndBeat {
                        projectManager.splitRegionAtPosition(region.id, trackId: track.id, splitBeat: playheadBeat)
                        splitCount += 1
                        break // Only split one region when nothing is selected
                    }
                }
                if splitCount > 0 { break }
            }
        }
        
        // Reload audio engine to pick up changes
        if splitCount > 0, let updatedProject = projectManager.currentProject {
            audioEngine.loadProject(updatedProject)
        }
    }
}


// Note: The following have been extracted to separate files:
// - TimelineHelpers.swift: BatchAnalysisState, AddTrackButtonStyle, TimelinePlayhead, CatchPlayheadObserver, SelectionCountBadge, AudioSelectionObserver, MarqueeOverlay
// - MIDIRegionPositioning.swift: MIDIRegionsLayer, PositionedMIDIRegion
// - AudioRegionPositioning.swift: AudioRegionsLayer, PositionedAudioRegion
// - IntegratedAudioRegion.swift: IntegratedAudioRegion
// - IntegratedTrackHeader.swift: IntegratedTrackHeader
// - AutomationCurveOverlay.swift: AutomationCurveOverlay
// - IntegratedGridBackground.swift: IntegratedGridBackground
// - IntegratedTrackRow.swift: IntegratedTrackRow
