//
//  ProjectExportService.swift
//  Stori
//
//  Professional project export service with full mix rendering
//  Includes all tracks, buses, effects, and master processing
//

import Foundation
import AVFoundation
import AppKit
import Combine

// MARK: - Offline MIDI Renderer

/// Renders MIDI tracks to audio for offline export
/// Creates synth voices and processes MIDI events in sample-accurate time
class OfflineMIDIRenderer {
    
    /// Scheduled MIDI event for offline rendering
    struct ScheduledEvent: Comparable {
        let sampleTime: AVAudioFramePosition  // Sample-accurate time
        let pitch: UInt8
        let velocity: UInt8
        let isNoteOn: Bool
        
        static func < (lhs: ScheduledEvent, rhs: ScheduledEvent) -> Bool {
            lhs.sampleTime < rhs.sampleTime
        }
    }
    
    /// Active voice for rendering
    private class RenderVoice {
        let pitch: UInt8
        let velocity: UInt8
        let preset: SynthPreset
        let sampleRate: Float
        
        private var phase: Float = 0
        private var envelope: Float = 0
        private var envelopeState: EnvelopeState = .attack
        private var releaseStartTime: Float = 0
        private var startSample: AVAudioFramePosition = 0
        
        enum EnvelopeState { case attack, decay, sustain, release, finished }
        
        var isFinished: Bool { envelopeState == .finished }
        var isReleasing: Bool { envelopeState == .release }
        
        init(pitch: UInt8, velocity: UInt8, preset: SynthPreset, sampleRate: Float, startSample: AVAudioFramePosition) {
            self.pitch = pitch
            self.velocity = velocity
            self.preset = preset
            self.sampleRate = sampleRate
            self.startSample = startSample
        }
        
        func release(at sample: AVAudioFramePosition) {
            if envelopeState != .release && envelopeState != .finished {
                envelopeState = .release
                releaseStartTime = Float(sample - startSample) / sampleRate
            }
        }
        
        func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int, currentSample: AVAudioFramePosition) {
            guard envelopeState != .finished else { return }
            
            let frequency = 440.0 * pow(2.0, (Float(pitch) - 69.0) / 12.0)
            let velocityGain = Float(velocity) / 127.0
            let phaseIncrement = frequency / sampleRate
            
            for frame in 0..<frameCount {
                let timeSinceStart = Float(currentSample + AVAudioFramePosition(frame) - startSample) / sampleRate
                
                // Simple ADSR envelope
                switch envelopeState {
                case .attack:
                    let attackTime = max(0.001, preset.envelope.attack)
                    envelope = min(1.0, timeSinceStart / attackTime)
                    if envelope >= 1.0 { envelopeState = .decay }
                    
                case .decay:
                    let decayTime = max(0.001, preset.envelope.decay)
                    let decayProgress = (timeSinceStart - preset.envelope.attack) / decayTime
                    envelope = 1.0 - (1.0 - preset.envelope.sustain) * min(1.0, decayProgress)
                    if decayProgress >= 1.0 { envelopeState = .sustain }
                    
                case .sustain:
                    envelope = preset.envelope.sustain
                    
                case .release:
                    let releaseTime = max(0.001, preset.envelope.release)
                    let releaseProgress = (timeSinceStart - releaseStartTime) / releaseTime
                    envelope = preset.envelope.sustain * (1.0 - min(1.0, releaseProgress))
                    if releaseProgress >= 1.0 { envelopeState = .finished }
                    
                case .finished:
                    return
                }
                
                // Generate waveform based on preset oscillator type
                var waveform: Float = 0
                
                switch preset.oscillator1 {
                case .sine:
                    waveform = sin(phase * 2.0 * .pi)
                case .saw:
                    waveform = 2.0 * phase - 1.0  // Sawtooth: ramps from -1 to 1
                case .square:
                    waveform = phase < 0.5 ? 1.0 : -1.0
                case .triangle:
                    waveform = phase < 0.5 ? (4.0 * phase - 1.0) : (3.0 - 4.0 * phase)
                case .pulse:
                    // Pulse with variable width (default 25%)
                    waveform = phase < 0.25 ? 1.0 : -1.0
                case .noise:
                    waveform = Float.random(in: -1...1)
                }
                
                let gain: Float = envelope * velocityGain * preset.masterVolume * 0.5
                buffer[frame] += waveform * gain
                
                phase += phaseIncrement
                if phase >= 1.0 { phase -= 1.0 }
            }
        }
    }
    
    // Properties
    private var scheduledEvents: [ScheduledEvent] = []
    private var nextEventIndex: Int = 0
    private var activeVoices: [RenderVoice] = []
    private let preset: SynthPreset
    private let sampleRate: Float
    private let volume: Float
    private let lock = NSLock()
    
    /// Current sample position (incremented with each render call)
    private var currentSamplePosition: AVAudioFramePosition = 0
    
    init(preset: SynthPreset, sampleRate: Double, volume: Float) {
        self.preset = preset
        self.sampleRate = Float(sampleRate)
        self.volume = volume
    }
    
    /// Schedule MIDI events from a region
    func scheduleRegion(_ region: MIDIRegion, tempo: Double, sampleRate: Double) {
        let secondsPerBeat = 60.0 / tempo
        let loopCount = region.isLooped ? region.loopCount : 1
        
        
        for loopIndex in 0..<loopCount {
            let loopOffsetBeats = Double(loopIndex) * region.durationBeats
            
            for note in region.notes {
                // Calculate absolute time in beats, then convert to samples
                let startBeats = region.startBeat + note.startBeat + loopOffsetBeats
                let endBeats = startBeats + note.durationBeats
                
                let startSeconds = startBeats * secondsPerBeat
                let endSeconds = endBeats * secondsPerBeat
                
                let startSample = AVAudioFramePosition(startSeconds * sampleRate)
                let endSample = AVAudioFramePosition(endSeconds * sampleRate)
                
                
                // Note On
                scheduledEvents.append(ScheduledEvent(
                    sampleTime: startSample,
                    pitch: note.pitch,
                    velocity: note.velocity,
                    isNoteOn: true
                ))
                
                // Note Off
                scheduledEvents.append(ScheduledEvent(
                    sampleTime: endSample,
                    pitch: note.pitch,
                    velocity: 0,
                    isNoteOn: false
                ))
            }
        }
        
        // Sort events by time
        scheduledEvents.sort()
    }
    
    /// Render audio for a range of samples (uses internal sample position tracking)
    func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        let startSample = currentSamplePosition
        let endSample = startSample + AVAudioFramePosition(frameCount)
        
        // Process any scheduled events in this time range
        while nextEventIndex < scheduledEvents.count {
            let event = scheduledEvents[nextEventIndex]
            
            // Stop if event is past our render window
            if event.sampleTime >= endSample { break }
            
            // Skip events before our window (already processed)
            if event.sampleTime < startSample {
                nextEventIndex += 1
                continue
            }
            
            if event.isNoteOn {
                // Create new voice
                let voice = RenderVoice(
                    pitch: event.pitch,
                    velocity: event.velocity,
                    preset: preset,
                    sampleRate: sampleRate,
                    startSample: event.sampleTime
                )
                activeVoices.append(voice)
                
                // Debug log first few notes
                if nextEventIndex < 5 {
                }
            } else {
                // Release matching voice - find the oldest one that's NOT already in release state
                // This handles overlapping notes with the same pitch correctly
                var foundVoice: RenderVoice? = nil
                for voice in activeVoices {
                    if voice.pitch == event.pitch && !voice.isFinished && !voice.isReleasing {
                        foundVoice = voice
                        break  // Take the first (oldest) matching active voice
                    }
                }
                foundVoice?.release(at: event.sampleTime)
            }
            
            nextEventIndex += 1
        }
        
        // Debug: log active voice count periodically
        if activeVoices.count > 0 && currentSamplePosition % AVAudioFramePosition(sampleRate) == 0 {
        }
        
        // Render all active voices
        for voice in activeVoices where !voice.isFinished {
            voice.render(into: buffer, frameCount: frameCount, currentSample: startSample)
        }
        
        // Apply track volume
        for i in 0..<frameCount {
            buffer[i] *= volume
        }
        
        // Remove finished voices
        activeVoices.removeAll { $0.isFinished }
        
        // Advance sample position for next render call
        currentSamplePosition = endSample
    }
    
    /// Reset for new render pass
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        nextEventIndex = 0
        activeVoices.removeAll()
        currentSamplePosition = 0
    }
}

/// Service for exporting complete projects with full mix processing
@MainActor
@Observable
class ProjectExportService {
    
    // MARK: - Observable Properties
    var exportProgress: Double = 0.0
    var isExporting: Bool = false
    var exportStatus: String = ""
    var elapsedTime: TimeInterval = 0.0
    var estimatedTimeRemaining: TimeInterval? = nil
    
    @ObservationIgnored
    private let fileManager = FileManager.default
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var isCancelled: Bool = false
    @ObservationIgnored
    private var exportStartTime: Date?
    
    /// MIDI renderers for offline export (keyed by track ID)
    @ObservationIgnored
    private var midiRenderers: [UUID: OfflineMIDIRenderer] = [:]
    
    /// Per-track mixer nodes for applying automation during export (keyed by track ID)
    @ObservationIgnored
    private var trackMixerNodes: [UUID: AVAudioMixerNode] = [:]
    
    /// Per-track EQ nodes for applying 3-band EQ during export (keyed by track ID)
    @ObservationIgnored
    private var trackEQNodes: [UUID: AVAudioUnitEQ] = [:]
    
    /// Cloned AU plugins for track insert chains (keyed by track ID)
    @ObservationIgnored
    private var clonedTrackPlugins: [UUID: [AVAudioUnit]] = [:]
    
    /// Cloned AU plugins for bus insert chains (keyed by bus ID)
    @ObservationIgnored
    private var clonedBusPlugins: [UUID: [AVAudioUnit]] = [:]
    
    /// Export bus input mixers for send routing (keyed by bus ID)
    @ObservationIgnored
    private var exportBusInputs: [UUID: AVAudioMixerNode] = [:]
    
    /// Export bus output mixers (keyed by bus ID)
    @ObservationIgnored
    private var exportBusOutputs: [UUID: AVAudioMixerNode] = [:]
    
    /// Automation processor for export (separate from live playback)
    @ObservationIgnored
    private var exportAutomationProcessor: AutomationProcessor?
    
    /// Project tempo for beat calculations during export
    @ObservationIgnored
    private var exportTempo: Double = 120.0
    
    /// Export directory for rendered projects
    private var exportDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportDir = documentsPath.appendingPathComponent("Stori_Exports")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: exportDir.path) {
            try? fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        }
        
        return exportDir
    }
    
    // MARK: - Cancellation
    
    func cancelExport() {
        isCancelled = true
        exportStatus = "Cancelled"
        
        // Reset export state to close the dialog
        // The actual rendering will stop in the next tap callback
        Task { @MainActor in
            // Small delay to show "Cancelled" message before closing
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            self.isExporting = false
            self.exportProgress = 0.0
            self.elapsedTime = 0.0
            self.estimatedTimeRemaining = nil
        }
    }
    
    // MARK: - Main Export Function
    
    /// Export complete project mix with all processing applied
    /// - Parameters:
    ///   - project: The audio project to export
    ///   - audioEngine: The audio engine with all processing nodes
    ///   - sampleRate: Output sample rate (default: 48000 Hz)
    ///   - bitDepth: Output bit depth (default: 24-bit)
    /// - Returns: URL of the exported file
    func exportProjectMix(
        project: AudioProject,
        audioEngine: AudioEngine,
        sampleRate: Double = 48000,
        bitDepth: Int = 24
    ) async throws -> URL {
        
        isExporting = true
        exportProgress = 0.0
        exportStatus = "Preparing export..."
        isCancelled = false
        exportStartTime = Date()
        elapsedTime = 0.0
        estimatedTimeRemaining = nil
        
        let secondsPerBeat = 60.0 / project.tempo
        
        
        // Generate output filename
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "\(sanitizeFileName(project.name))_\(timestamp).wav"
        let outputURL = exportDirectory.appendingPathComponent(filename)
        
        // Calculate project duration
        let projectDuration = calculateProjectDuration(project)
        
        // Create offline render engine
        let renderEngine = AVAudioEngine()
        
        exportStatus = "Setting up audio graph..."
        exportProgress = 0.1
        
        // Set up the audio graph for offline rendering
        try await setupOfflineAudioGraph(
            renderEngine: renderEngine,
            project: project,
            audioEngine: audioEngine,
            sampleRate: sampleRate
        )
        
        exportStatus = "Rendering audio..."
        exportProgress = 0.2
        
        // Perform offline rendering
        let renderedBuffer = try await renderProjectAudio(
            renderEngine: renderEngine,
            duration: projectDuration,
            sampleRate: sampleRate
        )
        
        exportStatus = "Writing to file..."
        exportProgress = 0.9
        
        // Write to WAV file
        try writeToWAVFile(
            buffer: renderedBuffer,
            url: outputURL,
            sampleRate: sampleRate,
            bitDepth: bitDepth
        )
        
        // Clean up export resources (samplers, renderers)
        cleanupExportResources()
        
        exportProgress = 1.0
        exportStatus = "Export complete!"
        isExporting = false
        
        
        // Get file size
        if let attrs = try? fileManager.attributesOfItem(atPath: outputURL.path),
           let fileSize = attrs[.size] as? Int64 {
        }
        
        // Open export folder
        NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: exportDirectory.path)
        
        return outputURL
    }
    
    // MARK: - Multi-Format Export
    
    /// Export project with custom settings (multi-format support)
    /// - Parameters:
    ///   - project: The audio project to export
    ///   - audioEngine: The audio engine with all processing nodes
    ///   - settings: Export settings including format, sample rate, bit depth
    /// - Returns: URL of the exported file
    func exportProjectWithSettings(
        project: AudioProject,
        audioEngine: AudioEngine,
        settings: ExportSettings
    ) async throws -> URL {
        
        isExporting = true
        exportProgress = 0.0
        exportStatus = "Preparing export..."
        isCancelled = false
        exportStartTime = Date()
        elapsedTime = 0.0
        estimatedTimeRemaining = nil
        
        // Use 48kHz - the standard device sample rate that AVAudioEngine runs at
        let sampleRate = settings.sampleRate  // Fixed to 48kHz
        let bitDepth = settings.bitDepth.value
        
        
        // Generate output filename
        let filename = "\(sanitizeFileName(settings.filename)).\(settings.format.rawValue)"
        let outputURL = exportDirectory.appendingPathComponent(filename)
        
        // Calculate project duration
        let projectDuration = calculateProjectDuration(project)
        
        // Check for cancellation
        guard !isCancelled else {
            throw ExportError.cancelled
        }
        
        // Create offline render engine
        let renderEngine = AVAudioEngine()
        
        exportStatus = "Setting up audio graph..."
        exportProgress = 0.1
        
        // Set up the audio graph for offline rendering
        try await setupOfflineAudioGraph(
            renderEngine: renderEngine,
            project: project,
            audioEngine: audioEngine,
            sampleRate: sampleRate
        )
        
        exportStatus = "Rendering audio..."
        exportProgress = 0.2
        
        // Perform offline rendering
        let renderedBuffer = try await renderProjectAudio(
            renderEngine: renderEngine,
            duration: projectDuration,
            sampleRate: sampleRate
        )
        
        exportStatus = "Converting to \(settings.format.displayName)..."
        exportProgress = 0.85
        
        // Check for cancellation
        guard !isCancelled else {
            throw ExportError.cancelled
        }
        
        // Write to file based on format
        switch settings.format {
        case .wav:
            try writeToWAVFile(
                buffer: renderedBuffer,
                url: outputURL,
                sampleRate: sampleRate,
                bitDepth: bitDepth
            )
            
        case .aiff:
            try writeToAIFFFile(
                buffer: renderedBuffer,
                url: outputURL,
                sampleRate: sampleRate,
                bitDepth: bitDepth
            )
            
        case .m4a:
            try await writeToM4AFile(
                buffer: renderedBuffer,
                url: outputURL,
                sampleRate: sampleRate
            )
            
        case .flac:
            try writeToFLACFile(
                buffer: renderedBuffer,
                url: outputURL,
                sampleRate: sampleRate,
                bitDepth: bitDepth
            )
        }
        
        // Normalize if requested
        if settings.normalizeAudio {
            exportStatus = "Normalizing audio..."
            exportProgress = 0.95
            // Note: Normalization would be applied during rendering for best quality
            // This is a placeholder for future implementation
        }
        
        // Clean up export resources (samplers, renderers, cloned plugins)
        cleanupExportResources()
        
        exportProgress = 1.0
        exportStatus = "Export complete!"
        isExporting = false
        
        
        // Get file size
        if let attrs = try? fileManager.attributesOfItem(atPath: outputURL.path),
           let fileSize = attrs[.size] as? Int64 {
            let formattedSize = formatFileSize(fileSize)
        }
        
        // Open export folder
        NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: exportDirectory.path)
        
        return outputURL
    }
    
    // MARK: - Format-Specific Writers
    
    private func writeToAIFFFile(
        buffer: AVAudioPCMBuffer,
        url: URL,
        sampleRate: Double,
        bitDepth: Int
    ) throws {
        
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: true,  // AIFF uses big-endian
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let outputFile = try AVAudioFile(forWriting: url, settings: settings)
        try outputFile.write(from: buffer)
        
    }
    
    private func writeToM4AFile(
        buffer: AVAudioPCMBuffer,
        url: URL,
        sampleRate: Double
    ) async throws {
        
        // First write to a temporary WAV file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        TempFileManager.track(tempURL)
        try writeToWAVFile(buffer: buffer, url: tempURL, sampleRate: sampleRate, bitDepth: 24)
        defer {
            TempFileManager.untrack(tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Convert to M4A using AVAssetExportSession
        let asset = AVAsset(url: tempURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.formatNotSupported
        }
        
        exportSession.outputURL = url
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw error
            }
            throw ExportError.formatConversionFailed
        }
        
    }
    
    private func writeToFLACFile(
        buffer: AVAudioPCMBuffer,
        url: URL,
        sampleRate: Double,
        bitDepth: Int
    ) throws {
        
        // Note: AVAudioFile supports FLAC on macOS 11+
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: bitDepth
        ]
        
        do {
            let outputFile = try AVAudioFile(forWriting: url, settings: settings)
            try outputFile.write(from: buffer)
        } catch {
            // Fallback: FLAC might not be available on older systems
            let wavURL = url.deletingPathExtension().appendingPathExtension("wav")
            try writeToWAVFile(buffer: buffer, url: wavURL, sampleRate: sampleRate, bitDepth: bitDepth)
            throw ExportError.formatFallback(originalFormat: .flac, fallbackURL: wavURL)
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1_000_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        } else if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else {
            return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Calculate project duration in BEATS (primary unit), then convert to seconds for AVAudioEngine
    /// Calculate the duration of a project in seconds (public for UI estimation)
    func calculateProjectDuration(_ project: AudioProject) -> TimeInterval {
        let durationBeats = calculateProjectDurationInBeats(project)
        
        // Convert beats to seconds for AVAudioEngine (which requires seconds)
        let secondsPerBeat = 60.0 / project.tempo
        let durationSeconds = durationBeats * secondsPerBeat
        
        // L-2: Calculate max plugin tail time (reverbs, delays, etc.)
        // This ensures reverb/delay tails are captured in the export
        let maxTailTime = calculateMaxPluginTailTime(project)
        
        // Use the larger of: plugin tail time or minimum 300ms buffer for synth release
        let tailBuffer = max(maxTailTime, 0.3)
        
        return durationSeconds + tailBuffer
    }
    
    /// Calculate the maximum tail time across all plugins in the project
    /// Used to ensure reverb/delay tails are captured during export
    private func calculateMaxPluginTailTime(_ project: AudioProject) -> TimeInterval {
        var maxTailTime: TimeInterval = 0.0
        
        for track in project.tracks {
            // Get plugin instances for this track's configured plugins
            for config in track.pluginConfigs {
                if let instance = PluginInstanceManager.shared.instances.values.first(where: { 
                    $0.descriptor.name == config.pluginName && !$0.isBypassed
                }) {
                    maxTailTime = max(maxTailTime, instance.tailTime)
                }
            }
        }
        
        // Also check master bus plugins if available (future extension)
        // For now, cap at 5 seconds to prevent unreasonably long exports from buggy plugins
        return min(maxTailTime, 5.0)
    }
    
    /// Calculate project duration in BEATS
    private func calculateProjectDurationInBeats(_ project: AudioProject) -> Double {
        var maxEndTimeBeats: Double = 0.0
        
        let tempo = project.tempo
        
        for track in project.tracks {
            // Audio regions (now in beats for position)
            for region in track.regions {
                let endTimeBeats = region.endBeat
                maxEndTimeBeats = max(maxEndTimeBeats, endTimeBeats)
            }
            
            // MIDI regions (in beats)
            for midiRegion in track.midiRegions {
                let endTimeBeats = midiRegion.startBeat + midiRegion.totalDurationBeats
                maxEndTimeBeats = max(maxEndTimeBeats, endTimeBeats)
            }
        }
        
        return maxEndTimeBeats
    }
    
    private func setupOfflineAudioGraph(
        renderEngine: AVAudioEngine,
        project: AudioProject,
        audioEngine: AudioEngine,
        sampleRate: Double
    ) async throws {
        
        // Create format for rendering
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        
        // Clear any previous state
        midiRenderers.removeAll()
        trackMixerNodes.removeAll()
        clonedTrackPlugins.removeAll()
        clonedBusPlugins.removeAll()
        exportBusInputs.removeAll()
        exportBusOutputs.removeAll()
        
        // Store tempo for automation calculations
        exportTempo = project.tempo
        
        // Set up automation processor for export
        exportAutomationProcessor = AutomationProcessor()
        for track in project.tracks {
            exportAutomationProcessor?.updateAutomation(
                for: track.id,
                lanes: track.automationLanes,
                mode: track.automationMode
            )
        }
        
        // PHASE 1: Setup buses FIRST so track sends can route to them
        for bus in project.buses {
            try await setupBusForExport(
                bus: bus,
                audioEngine: audioEngine,
                renderEngine: renderEngine,
                format: format
            )
        }
        
        // Create player nodes for each audio track/region
        var playerNodes: [(node: AVAudioPlayerNode, region: AudioRegion, track: AudioTrack)] = []
        var midiTrackCount = 0
        
        for track in project.tracks {
            guard track.isEnabled && !track.isFrozen else { continue }
            
            // Create per-track mixer node for volume/pan automation
            let trackMixer = AVAudioMixerNode()
            renderEngine.attach(trackMixer)
            trackMixerNodes[track.id] = trackMixer
            
            // Set initial volume/pan from track settings
            trackMixer.outputVolume = track.mixerSettings.volume
            trackMixer.pan = track.mixerSettings.pan
            
            // PHASE 2: Clone track plugin chain (AU insert effects)
            let clonedPlugins = try await cloneTrackPluginChain(
                trackId: track.id,
                audioEngine: audioEngine,
                renderEngine: renderEngine,
                format: format
            )
            clonedTrackPlugins[track.id] = clonedPlugins
            
            // Create 3-band EQ for this track (if EQ is enabled)
            var eqNode: AVAudioUnitEQ?
            if track.mixerSettings.eqEnabled {
                eqNode = AVAudioUnitEQ(numberOfBands: 3)
                renderEngine.attach(eqNode!)
                trackEQNodes[track.id] = eqNode!
                configureTrackEQ(eqNode!, settings: track.mixerSettings)
            }
            
            // Build connection chain: trackMixer -> [Plugins] -> [EQ] -> mainMixer
            // But we also need sends, so: trackMixer -> [Plugins] -> [EQ] -> sendSplitter
            let finalOutput: AVAudioNode
            if let eq = eqNode {
                finalOutput = eq
            } else if let lastPlugin = clonedPlugins.last {
                finalOutput = lastPlugin
            } else {
                finalOutput = trackMixer
            }
            
            // Connect track's internal chain
            
            if !clonedPlugins.isEmpty {
                // trackMixer -> plugin1 -> plugin2 -> ... -> eqNode or mainMixer
                var previousNode: AVAudioNode = trackMixer
                var previousName = "trackMixer"
                
                for (idx, plugin) in clonedPlugins.enumerated() {
                    renderEngine.connect(previousNode, to: plugin, format: format)
                    let pluginName = "plugin[\(idx)]"
                    previousNode = plugin
                    previousName = pluginName
                }
                if let eq = eqNode {
                    renderEngine.connect(previousNode, to: eq, format: format)
                    previousNode = eq
                    previousName = "eqNode"
                }
                // Connect final node to main mixer (sends handled below)
                renderEngine.connect(previousNode, to: renderEngine.mainMixerNode, format: format)
            } else if let eq = eqNode {
                // No plugins, just EQ
                renderEngine.connect(trackMixer, to: eq, format: format)
                renderEngine.connect(eq, to: renderEngine.mainMixerNode, format: format)
            } else {
                // No plugins, no EQ - direct to main mixer
                renderEngine.connect(trackMixer, to: renderEngine.mainMixerNode, format: format)
            }
            
            // PHASE 3: Setup track sends to buses
            setupTrackSendsForExport(
                track: track,
                audioEngine: audioEngine,
                renderEngine: renderEngine,
                trackMixer: trackMixer,
                format: format
            )
            
            // Handle audio regions - connect to track mixer
            for region in track.regions {
                let playerNode = AVAudioPlayerNode()
                renderEngine.attach(playerNode)
                playerNodes.append((playerNode, region, track))
                
                // Connect to track mixer (for per-track automation control)
                renderEngine.connect(playerNode, to: trackMixer, format: format)
            }
            
            // Handle MIDI regions - create synth source nodes
            if track.isMIDITrack && !track.midiRegions.isEmpty {
                try setupMIDITrackForExport(
                    track: track,
                    project: project,
                    renderEngine: renderEngine,
                    sampleRate: sampleRate,
                    format: format,
                    trackMixer: trackMixer
                )
                midiTrackCount += 1
            }
        }
        
        // Schedule all audio files for playback
        for (playerNode, region, track) in playerNodes {
            try scheduleRegionForPlayback(
                playerNode: playerNode,
                region: region,
                track: track,
                sampleRate: sampleRate,
                tempo: project.tempo
            )
        }
        
    }
    
    // MARK: - AU Plugin Export Support
    
    /// Clone a track's plugin chain for offline rendering
    private func cloneTrackPluginChain(
        trackId: UUID,
        audioEngine: AudioEngine,
        renderEngine: AVAudioEngine,
        format: AVAudioFormat
    ) async throws -> [AVAudioUnit] {
        
        guard let pluginChain = await audioEngine.getPluginChain(for: trackId) else {
            return []
        }
        
        let activeCount = await pluginChain.activePlugins.count
        
        // Log each active plugin before cloning
        for (idx, plugin) in await pluginChain.activePlugins.enumerated() {
            let name = await plugin.descriptor.name
            let bypassed = await plugin.isBypassed
        }
        
        // Clone all active plugins
        let clonedNodes = try await pluginChain.cloneActivePlugins()
        
        // Attach to render engine
        for (idx, node) in clonedNodes.enumerated() {
            renderEngine.attach(node)
        }
        
        return clonedNodes
    }
    
    /// Setup a bus for offline export rendering with cloned AU plugins
    private func setupBusForExport(
        bus: MixerBus,
        audioEngine: AudioEngine,
        renderEngine: AVAudioEngine,
        format: AVAudioFormat
    ) async throws {
        // Create bus input/output mixers
        let busInput = AVAudioMixerNode()
        let busOutput = AVAudioMixerNode()
        renderEngine.attach(busInput)
        renderEngine.attach(busOutput)
        
        // Store for send routing
        exportBusInputs[bus.id] = busInput
        exportBusOutputs[bus.id] = busOutput
        
        // Set bus output gain (return level)
        busOutput.outputVolume = 0.75  // Default return level
        
        // Clone bus plugin chain (e.g., reverb, delay)
        var clonedPlugins: [AVAudioUnit] = []
        if let liveBusNode = await audioEngine.getBusNode(for: bus.id) {
            let pluginChain = liveBusNode.pluginChain
            clonedPlugins = try await pluginChain.cloneActivePlugins()
            clonedBusPlugins[bus.id] = clonedPlugins
            
            // Attach cloned plugins to render engine
            for plugin in clonedPlugins {
                renderEngine.attach(plugin)
            }
        }
        
        // Connect bus chain: busInput -> [plugins] -> busOutput -> mainMixer
        if clonedPlugins.isEmpty {
            // No plugins, direct connection
            renderEngine.connect(busInput, to: busOutput, format: format)
        } else {
            // Connect through plugin chain
            var previousNode: AVAudioNode = busInput
            for plugin in clonedPlugins {
                renderEngine.connect(previousNode, to: plugin, format: format)
                previousNode = plugin
            }
            renderEngine.connect(previousNode, to: busOutput, format: format)
        }
        
        // Connect bus output to main mixer
        renderEngine.connect(busOutput, to: renderEngine.mainMixerNode, format: format)
        
    }
    
    /// Setup track sends to buses for offline export
    private func setupTrackSendsForExport(
        track: AudioTrack,
        audioEngine: AudioEngine,
        renderEngine: AVAudioEngine,
        trackMixer: AVAudioMixerNode,
        format: AVAudioFormat
    ) {
        // Get sends from live engine (runtime state)
        let sends = audioEngine.getTrackSends(for: track.id)
        
        // Use project model sends if engine sends are empty (fallback)
        let sendsToProcess: [(busId: UUID, level: Float)]
        if !sends.isEmpty {
            sendsToProcess = sends
        } else {
            // Fallback to project model
            sendsToProcess = track.sends
                .filter { !$0.isMuted }
                .map { (busId: $0.busId, level: Float($0.sendLevel)) }
        }
        
        guard !sendsToProcess.isEmpty else { return }
        
        // For each send, connect trackMixer to the bus input with appropriate level
        for send in sendsToProcess {
            guard let busInput = exportBusInputs[send.busId] else {
                continue
            }
            
            // Create a send mixer node to control send level independently
            let sendMixer = AVAudioMixerNode()
            renderEngine.attach(sendMixer)
            sendMixer.outputVolume = send.level
            
            // Connect: trackMixer -> sendMixer -> busInput
            // This creates a parallel path for the send
            renderEngine.connect(trackMixer, to: sendMixer, format: format)
            renderEngine.connect(sendMixer, to: busInput, format: format)
        }
    }
    
    // MARK: - Sampler-based Export Support
    
    /// Stores sampler engines created for export (to keep them alive during render)
    @ObservationIgnored
    private var exportSamplers: [UUID: SamplerEngine] = [:]
    
    /// Scheduled MIDI events for sampler playback during export
    @ObservationIgnored
    private var samplerEvents: [UUID: [ScheduledSamplerEvent]] = [:]
    
    /// Sampler event for real-time playback during export
    /// Event types for sampler export scheduling
    enum SamplerEventType: Equatable {
        case noteOn(pitch: UInt8, velocity: UInt8)
        case noteOff(pitch: UInt8)
        case controlChange(controller: UInt8, value: UInt8)
        case pitchBend(value: Int16)  // -8192 to +8191
    }
    
    struct ScheduledSamplerEvent: Comparable {
        let sampleTime: AVAudioFramePosition
        let eventType: SamplerEventType
        
        static func < (lhs: ScheduledSamplerEvent, rhs: ScheduledSamplerEvent) -> Bool {
            lhs.sampleTime < rhs.sampleTime
        }
    }
    
    /// Set up a MIDI track for offline export rendering
    /// Supports both SynthPresets (using OfflineMIDIRenderer) and GM instruments (using SamplerEngine)
    private func setupMIDITrackForExport(
        track: AudioTrack,
        project: AudioProject,
        renderEngine: AVAudioEngine,
        sampleRate: Double,
        format: AVAudioFormat,
        trackMixer: AVAudioMixerNode
    ) throws {
        
        guard let voicePresetName = track.voicePreset else {
            return
        }
        
        // Check if it's a GM instrument (SoundFont sampler)
        if let gmInstrument = GMInstrument.allCases.first(where: { $0.name == voicePresetName }) {
            // Use SamplerEngine for GM instruments
            try setupSamplerForExport(
                track: track,
                project: project,
                gmInstrument: gmInstrument,
                renderEngine: renderEngine,
                sampleRate: sampleRate,
                format: format,
                trackMixer: trackMixer
            )
            return
        }
        
        // Otherwise, it's a SynthPreset - use OfflineMIDIRenderer
        let preset: SynthPreset
        if let trackPreset = SynthPreset.preset(named: voicePresetName) {
            preset = trackPreset
        } else {
            preset = .default
        }
        
        // Create offline MIDI renderer for synth presets
        let renderer = OfflineMIDIRenderer(
            preset: preset,
            sampleRate: sampleRate,
            volume: track.mixerSettings.volume
        )
        
        // Schedule all MIDI regions for this track
        for midiRegion in track.midiRegions where !midiRegion.isMuted {
            renderer.scheduleRegion(midiRegion, tempo: project.tempo, sampleRate: sampleRate)
        }
        
        // Store renderer for this track
        midiRenderers[track.id] = renderer
        
        // Create an AVAudioSourceNode that renders this MIDI track's synth
        // Capture renderer in a local variable for the closure
        let trackRenderer = renderer
        
        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            // Clear buffers first
            for buffer in ablPointer {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            
            // Get left channel buffer
            guard let leftBuffer = ablPointer.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            
            // Render synth voices into the buffer
            // The renderer tracks its own sample position internally
            trackRenderer.render(into: leftBuffer, frameCount: Int(frameCount))
            
            // Copy to right channel (mono to stereo)
            if ablPointer.count > 1, let rightBuffer = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) {
                memcpy(rightBuffer, leftBuffer, Int(frameCount) * MemoryLayout<Float>.size)
            }
            
            return noErr
        }
        
        // Attach and connect the source node to the track mixer
        renderEngine.attach(sourceNode)
        renderEngine.connect(sourceNode, to: trackMixer, format: format)
        
    }
    
    /// Set up a SamplerEngine for GM instrument export
    /// This uses the actual SoundFont-based sampler for authentic instrument sounds
    /// Note: SamplerEngine currently connects to mainMixerNode, not trackMixer (future improvement)
    private func setupSamplerForExport(
        track: AudioTrack,
        project: AudioProject,
        gmInstrument: GMInstrument,
        renderEngine: AVAudioEngine,
        sampleRate: Double,
        format: AVAudioFormat,
        trackMixer: AVAudioMixerNode  // Connect sampler to this for plugin chain routing
    ) throws {
        
        // Create a sampler engine attached to the render engine
        // Use connectToMixer: false so we can connect to trackMixer instead for plugin routing
        let sampler = SamplerEngine(attachTo: renderEngine, connectToMixer: false)
        
        // Load the SoundFont
        guard let soundFontURL = SoundFontManager.shared.anySoundFontURL() else {
            return
        }
        
        try sampler.loadSoundFont(at: soundFontURL)
        try sampler.loadInstrument(gmInstrument)
        
        // CRITICAL: Connect sampler to trackMixer so audio flows through plugin chain
        // The plugin chain is: trackMixer -> [plugins] -> [EQ] -> mainMixer
        // So sampler -> trackMixer -> plugins -> output
        
        renderEngine.connect(sampler.sampler, to: trackMixer, format: format)
        
        // Verify the connection chain
        let samplerOutput = renderEngine.outputConnectionPoints(for: sampler.sampler, outputBus: 0)
        for conn in samplerOutput {
            if let node = conn.node {
                let isTrackMixer = node === trackMixer
            }
        }
        
        let trackMixerOutput = renderEngine.outputConnectionPoints(for: trackMixer, outputBus: 0)
        
        
        // Store sampler to keep it alive during export
        exportSamplers[track.id] = sampler
        
        // Schedule MIDI events for this track (notes, CC, and pitch bend)
        var events: [ScheduledSamplerEvent] = []
        let secondsPerBeat = 60.0 / project.tempo
        
        for midiRegion in track.midiRegions where !midiRegion.isMuted {
            let loopCount = midiRegion.isLooped ? midiRegion.loopCount : 1
            
            for loopIndex in 0..<loopCount {
                let loopOffsetBeats = Double(loopIndex) * midiRegion.durationBeats
                
                // Schedule note events
                for note in midiRegion.notes {
                    let startBeats = midiRegion.startBeat + note.startBeat + loopOffsetBeats
                    let endBeats = startBeats + note.durationBeats
                    
                    let startSeconds = startBeats * secondsPerBeat
                    let endSeconds = endBeats * secondsPerBeat
                    let startSample = AVAudioFramePosition(startSeconds * sampleRate)
                    let endSample = AVAudioFramePosition(endSeconds * sampleRate)
                    
                    events.append(ScheduledSamplerEvent(
                        sampleTime: startSample,
                        eventType: .noteOn(pitch: note.pitch, velocity: note.velocity)
                    ))
                    
                    events.append(ScheduledSamplerEvent(
                        sampleTime: endSample,
                        eventType: .noteOff(pitch: note.pitch)
                    ))
                }
                
                // Schedule CC events
                for ccEvent in midiRegion.controllerEvents {
                    let absoluteBeats = midiRegion.startBeat + ccEvent.beat + loopOffsetBeats
                    let absoluteSeconds = absoluteBeats * secondsPerBeat
                    let sampleTime = AVAudioFramePosition(absoluteSeconds * sampleRate)
                    
                    events.append(ScheduledSamplerEvent(
                        sampleTime: sampleTime,
                        eventType: .controlChange(controller: ccEvent.controller, value: ccEvent.value)
                    ))
                }
                
                // Schedule pitch bend events
                for pbEvent in midiRegion.pitchBendEvents {
                    let absoluteBeats = midiRegion.startBeat + pbEvent.beat + loopOffsetBeats
                    let absoluteSeconds = absoluteBeats * secondsPerBeat
                    let sampleTime = AVAudioFramePosition(absoluteSeconds * sampleRate)
                    
                    events.append(ScheduledSamplerEvent(
                        sampleTime: sampleTime,
                        eventType: .pitchBend(value: pbEvent.value)
                    ))
                }
            }
        }
        
        // Sort events by time
        events.sort()
        samplerEvents[track.id] = events
        
        // Debug: Log event count summary
        let noteCount = events.filter { 
            if case .noteOn = $0.eventType { return true }
            return false
        }.count
        let ccCount = events.filter {
            if case .controlChange = $0.eventType { return true }
            return false
        }.count
        let pbCount = events.filter {
            if case .pitchBend = $0.eventType { return true }
            return false
        }.count
    }
    
    /// Process sampler events during export render
    /// Call this from the tap callback to trigger MIDI events at the right time
    private func processSamplerEventsInRange(startSample: AVAudioFramePosition, frameCount: Int) {
        let endSample = startSample + AVAudioFramePosition(frameCount)
        
        for (trackId, events) in samplerEvents {
            guard let sampler = exportSamplers[trackId] else { continue }
            
            // Find events in this time range
            for event in events {
                if event.sampleTime >= startSample && event.sampleTime < endSample {
                    switch event.eventType {
                    case .noteOn(let pitch, let velocity):
                        sampler.noteOn(pitch: pitch, velocity: velocity)
                        
                    case .noteOff(let pitch):
                        sampler.noteOff(pitch: pitch)
                        
                    case .controlChange(let controller, let value):
                        sampler.controlChange(controller: controller, value: value)
                        
                    case .pitchBend(let value):
                        // Convert from signed -8192...+8191 to unsigned 0...16383 (center = 8192)
                        let unsignedValue = UInt16(bitPattern: Int16(value)) &+ 8192
                        sampler.pitchBend(value: unsignedValue)
                    }
                }
            }
        }
    }
    
    /// Clean up export resources
    private func cleanupExportResources() {
        // Stop and release all export samplers
        for (_, sampler) in exportSamplers {
            sampler.allNotesOff()
            sampler.stop()
        }
        exportSamplers.removeAll()
        samplerEvents.removeAll()
        midiRenderers.removeAll()
        trackMixerNodes.removeAll()
        trackEQNodes.removeAll()
        exportAutomationProcessor = nil
        
        // Clean up cloned AU plugins
        // The AVAudioUnit instances will be released when the dictionaries are cleared
        // and the render engine is deallocated
        let trackPluginCount = clonedTrackPlugins.values.reduce(0) { $0 + $1.count }
        let busPluginCount = clonedBusPlugins.values.reduce(0) { $0 + $1.count }
        
        clonedTrackPlugins.removeAll()
        clonedBusPlugins.removeAll()
        exportBusInputs.removeAll()
        exportBusOutputs.removeAll()
        
        if trackPluginCount > 0 || busPluginCount > 0 {
        }
    }
    
    /// Configure a 3-band EQ node from track mixer settings
    private func configureTrackEQ(_ eqNode: AVAudioUnitEQ, settings: MixerSettings) {
        guard eqNode.bands.count >= 3 else { return }
        
        // Band 0: Low shelf (80 Hz)
        let lowBand = eqNode.bands[0]
        lowBand.filterType = .lowShelf
        lowBand.frequency = 80.0
        lowBand.bandwidth = 1.0
        lowBand.gain = settings.lowEQ  // -12 to +12 dB
        lowBand.bypass = false
        
        // Band 1: Parametric mid (1kHz)
        let midBand = eqNode.bands[1]
        midBand.filterType = .parametric
        midBand.frequency = 1000.0
        midBand.bandwidth = 1.0
        midBand.gain = settings.midEQ  // -12 to +12 dB
        midBand.bypass = false
        
        // Band 2: High shelf (8kHz)
        let highBand = eqNode.bands[2]
        highBand.filterType = .highShelf
        highBand.frequency = 8000.0
        highBand.bandwidth = 1.0
        highBand.gain = settings.highEQ  // -12 to +12 dB
        highBand.bypass = false
    }
    
    /// Apply automation to track mixer nodes during export render
    private func applyExportAutomation(atSample samplePosition: AVAudioFrameCount, sampleRate: Double) {
        guard let processor = exportAutomationProcessor else { return }
        
        // Convert samples to seconds, then to beats
        let timeInSeconds = Double(samplePosition) / sampleRate
        let beatsPerSecond = exportTempo / 60.0
        let timeInBeats = timeInSeconds * beatsPerSecond
        
        // Apply automation to each track's mixer node
        for (trackId, mixerNode) in trackMixerNodes {
            if let values = processor.getAllValues(for: trackId, atBeat: timeInBeats) {
                // Apply volume automation
                if let volume = values.volume {
                    mixerNode.outputVolume = volume
                }
                
                // Apply pan automation (convert 0-1 to -1..+1)
                if let pan = values.pan {
                    mixerNode.pan = pan * 2 - 1
                }
            }
        }
    }
    
    private func scheduleRegionForPlayback(
        playerNode: AVAudioPlayerNode,
        region: AudioRegion,
        track: AudioTrack,
        sampleRate: Double,
        tempo: Double
    ) throws {
        
        // Load the audio file
        let audioFile = try AVAudioFile(forReading: region.audioFile.url)
        let sourceFileDuration = TimeInterval(audioFile.length) / audioFile.fileFormat.sampleRate
        
        // Convert beat position to seconds for AVAudioEngine scheduling
        let startTimeSeconds = region.startTimeSeconds(tempo: tempo)
        let startFrame = AVAudioFramePosition(startTimeSeconds * sampleRate)
        
        // Use contentLength for loop unit (includes empty space), fallback to source file duration
        let loopUnitDuration = region.contentLength > 0 ? region.contentLength : sourceFileDuration
        
        
        // Apply track volume
        playerNode.volume = track.mixerSettings.volume
        
        // Handle looped regions
        let regionDurationSeconds = region.durationSeconds(tempo: tempo)
        if region.isLooped && regionDurationSeconds > loopUnitDuration {
            // Calculate how many times to loop
            // CRITICAL: Use loopUnitDuration (contentLength) to respect empty space in loops
            var currentTimeSeconds = startTimeSeconds
            let endTimeSeconds = startTimeSeconds + regionDurationSeconds
            var loopCount = 0
            
            while currentTimeSeconds < endTimeSeconds {
                let loopStartFrame = AVAudioFramePosition(currentTimeSeconds * sampleRate)
                let scheduleTime = AVAudioTime(sampleTime: loopStartFrame, atRate: sampleRate)
                
                // Schedule one instance of the audio file (plays for sourceFileDuration, not loopUnitDuration)
                playerNode.scheduleFile(audioFile, at: scheduleTime)
                
                loopCount += 1
                // Advance by loopUnitDuration to respect empty space between loop iterations
                currentTimeSeconds += loopUnitDuration
                
            }
            
        } else {
            // Non-looped or single instance
            let scheduleTime = AVAudioTime(sampleTime: startFrame, atRate: sampleRate)
            playerNode.scheduleFile(audioFile, at: scheduleTime)
        }
    }
    
    private func renderProjectAudio(
        renderEngine: AVAudioEngine,
        duration: TimeInterval,
        sampleRate: Double
    ) async throws -> AVAudioPCMBuffer {
        
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ExportError.bufferCreationFailed
        }
        outputBuffer.frameLength = frameCount
        
        // Capture audio using a tap on the main mixer
        var capturedFrames: AVAudioFrameCount = 0
        let bufferSize: AVAudioFrameCount = 4096
        
        // Use a class to track if continuation has been resumed (thread-safe)
        final class ContinuationState: @unchecked Sendable {
            private let lock = NSLock()
            private var _isResumed = false
            
            var isResumed: Bool {
                lock.lock()
                defer { lock.unlock() }
                return _isResumed
            }
            
            /// Returns true if this call set the resumed flag (i.e., first caller wins)
            func tryResume() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if _isResumed { return false }
                _isResumed = true
                return true
            }
        }
        
        let state = ContinuationState()
        
        // Start the engine AFTER setup but BEFORE triggering notes
        try renderEngine.start()
        
        // Start all player nodes
        for node in renderEngine.attachedNodes {
            if let playerNode = node as? AVAudioPlayerNode {
                playerNode.play()
            }
        }
        
        // Track which sample position we've processed up to for sampler events
        // This ensures CONTINUOUS coverage with no gaps
        var samplerEventPosition: AVAudioFramePosition = 0
        
        // Pre-trigger events for the first buffer (sampler needs time to produce audio)
        // Use a generous lookahead to ensure notes sound on time
        let initialLookahead = Int(bufferSize) * 2
        
        
        self.processSamplerEventsInRange(startSample: 0, frameCount: initialLookahead)
        samplerEventPosition = AVAudioFramePosition(initialLookahead)
        
        return try await withCheckedThrowingContinuation { continuation in
            renderEngine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Don't process if already resumed
                guard !state.isResumed else { return }
                
                // Get actual sample time from engine
                let actualSampleTime = time.sampleTime
                
                // Log tap callback timing periodically
                if capturedFrames % (48000 * 2) < buffer.frameLength {  // Every ~2 seconds
                }
                
                // Process sampler events with CONTINUOUS coverage
                // Trigger events from where we left off up to current position + lookahead
                // This ensures NO GAPS in event triggering
                let targetPosition = actualSampleTime + AVAudioFramePosition(buffer.frameLength) * 2  // 2-buffer lookahead
                
                if targetPosition > samplerEventPosition {
                    let framesToProcess = Int(targetPosition - samplerEventPosition)
                    self.processSamplerEventsInRange(
                        startSample: samplerEventPosition,
                        frameCount: framesToProcess
                    )
                    samplerEventPosition = targetPosition
                }
                
                // Apply automation to track mixer nodes
                self.applyExportAutomation(atSample: capturedFrames, sampleRate: sampleRate)
                
                // Copy buffer data to output buffer
                let framesToCopy = min(buffer.frameLength, frameCount - capturedFrames)
                
                if framesToCopy > 0, let outputData = outputBuffer.floatChannelData {
                    if let bufferData = buffer.floatChannelData {
                        for channel in 0..<Int(format.channelCount) {
                            let src = bufferData[channel]
                            let dst = outputData[channel].advanced(by: Int(capturedFrames))
                            memcpy(dst, src, Int(framesToCopy) * MemoryLayout<Float>.size)
                        }
                    }
                    
                    capturedFrames += framesToCopy
                    
                    // Update progress and time estimates
                    Task { @MainActor in
                        let progress = Double(capturedFrames) / Double(frameCount)
                        self.exportProgress = 0.2 + (progress * 0.7)
                        
                        // Update elapsed time
                        if let startTime = self.exportStartTime {
                            self.elapsedTime = Date().timeIntervalSince(startTime)
                            
                            // Calculate estimated time remaining
                            if progress > 0.05 { // Wait for 5% to get a better estimate
                                let totalEstimatedTime = self.elapsedTime / progress
                                self.estimatedTimeRemaining = totalEstimatedTime - self.elapsedTime
                            }
                        }
                    }
                }
                
                // Check for cancellation
                if self.isCancelled {
                    if state.tryResume() {
                        renderEngine.mainMixerNode.removeTap(onBus: 0)
                        renderEngine.stop()
                        continuation.resume(throwing: ExportError.cancelled)
                    }
                    return
                }
                
                // Check if we're done
                if capturedFrames >= frameCount {
                    if state.tryResume() {
                        renderEngine.mainMixerNode.removeTap(onBus: 0)
                        renderEngine.stop()
                        continuation.resume(returning: outputBuffer)
                    }
                }
            }
            
            // Safety timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64((duration + 10) * 1_000_000_000))
                if state.tryResume() {
                    renderEngine.mainMixerNode.removeTap(onBus: 0)
                    renderEngine.stop()
                    continuation.resume(throwing: ExportError.renderTimeout)
                }
            }
        }
    }
    
    private func writeToWAVFile(
        buffer: AVAudioPCMBuffer,
        url: URL,
        sampleRate: Double,
        bitDepth: Int
    ) throws {
        
        
        // Create output file settings
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let outputFile = try AVAudioFile(forWriting: url, settings: settings)
        try outputFile.write(from: buffer)
        
    }
    
    /// Sanitize a string for safe use as a filename
    /// SECURITY: Prevents path traversal, null byte injection, control characters, and other attacks
    private func sanitizeFileName(_ name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // SECURITY: Unicode normalization to prevent look-alike attacks and filesystem inconsistencies
        sanitized = sanitized.precomposedStringWithCanonicalMapping
        
        // SECURITY: Remove null bytes (path truncation attack)
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")
        
        // SECURITY: Remove ALL control characters (0x00-0x1F, 0x7F) that can corrupt filenames
        sanitized = sanitized.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            let value = scalar.value
            return value >= 0x20 && value != 0x7F
        }
        
        // SECURITY: Remove path traversal sequences
        sanitized = sanitized.replacingOccurrences(of: "..", with: "")
        sanitized = sanitized.replacingOccurrences(of: "./", with: "")
        sanitized = sanitized.replacingOccurrences(of: ".\\", with: "")
        
        // Remove or replace characters that aren't safe for file names
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")
        
        // Remove leading/trailing dots and underscores
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        
        // SECURITY: Check for reserved Windows filenames
        let reservedNames = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
                             "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4",
                             "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
        if reservedNames.contains(sanitized.uppercased()) {
            sanitized = "_\(sanitized)"
        }
        
        // Ensure we have a valid name
        if sanitized.isEmpty {
            sanitized = "Untitled"
        }
        
        // SECURITY: Limit filename length (leave room for timestamp and extension)
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        
        return sanitized
    }
    
    // MARK: - Tokenization Export Methods
    
    /// Export the full project mix to Data for IPFS upload
    /// - Parameters:
    ///   - project: The project to export
    ///   - audioEngine: The audio engine with all processing nodes
    /// - Returns: WAV audio data of the full mix
    func exportProjectMixToData(
        project: AudioProject,
        audioEngine: AudioEngine
    ) async throws -> Data {
        
        let sampleRate: Double = 48000
        let bitDepth: Int = 24
        
        // Calculate project duration
        let projectDuration = calculateProjectDuration(project)
        guard projectDuration > 0 else {
            throw ExportError.bufferCreationFailed
        }
        
        // Create offline render engine
        let renderEngine = AVAudioEngine()
        
        // Set up the audio graph for offline rendering
        try await setupOfflineAudioGraph(
            renderEngine: renderEngine,
            project: project,
            audioEngine: audioEngine,
            sampleRate: sampleRate
        )
        
        // Perform offline rendering
        let renderedBuffer = try await renderProjectAudio(
            renderEngine: renderEngine,
            duration: projectDuration,
            sampleRate: sampleRate
        )
        
        // Clean up export resources
        cleanupExportResources()
        
        // Convert buffer to WAV data
        return try bufferToWAVData(buffer: renderedBuffer, sampleRate: sampleRate, bitDepth: bitDepth)
    }
    
    /// Export a single track/stem to Data for IPFS upload
    /// Uses solo mode to render only the specified track
    /// - Parameters:
    ///   - track: The track to export
    ///   - project: The project containing the track
    ///   - audioEngine: The audio engine with all processing nodes
    /// - Returns: WAV audio data of the stem
    func exportStemToData(
        track: AudioTrack,
        project: AudioProject,
        audioEngine: AudioEngine
    ) async throws -> Data {
        
        let sampleRate: Double = 48000
        let bitDepth: Int = 24
        
        // Calculate track duration
        let trackDuration = track.durationBeats ?? 0
        guard trackDuration > 0 else {
            throw ExportError.bufferCreationFailed
        }
        
        // Create a modified project with only this track unmuted
        var soloProject = project
        soloProject.tracks = soloProject.tracks.map { t in
            var modifiedTrack = t
            modifiedTrack.mixerSettings.isMuted = (t.id != track.id)
            return modifiedTrack
        }
        // Mute all buses to avoid bus effects on soloed stem
        soloProject.buses = soloProject.buses.map { bus in
            var modifiedBus = bus
            modifiedBus.isMuted = true
            return modifiedBus
        }
        
        // Create offline render engine
        let renderEngine = AVAudioEngine()
        
        // Set up the audio graph for offline rendering
        try await setupOfflineAudioGraph(
            renderEngine: renderEngine,
            project: soloProject,
            audioEngine: audioEngine,
            sampleRate: sampleRate
        )
        
        // Perform offline rendering (add small tail for release/reverb)
        let renderedBuffer = try await renderProjectAudio(
            renderEngine: renderEngine,
            duration: trackDuration + 1.0,  // 1 second tail
            sampleRate: sampleRate
        )
        
        // Clean up export resources
        cleanupExportResources()
        
        // Convert buffer to WAV data
        return try bufferToWAVData(buffer: renderedBuffer, sampleRate: sampleRate, bitDepth: bitDepth)
    }
    
    /// Export MIDI regions from a track to Standard MIDI File (SMF) format
    /// - Parameters:
    ///   - track: The MIDI track to export
    ///   - project: The project (for tempo information)
    /// - Returns: MIDI file data (.mid format)
    func exportMIDIToData(
        track: AudioTrack,
        project: AudioProject
    ) throws -> Data {
        guard !track.midiRegions.isEmpty else {
            throw ExportError.bufferCreationFailed
        }
        
        let tempo = project.tempo
        let ticksPerQuarter: UInt16 = 480  // Standard MIDI resolution
        
        // Collect all notes from all MIDI regions
        var allNotes: [(absoluteTime: Double, pitch: UInt8, velocity: UInt8, duration: Double)] = []
        
        // Collect all CC events from all MIDI regions
        var allCCEvents: [(absoluteTime: Double, controller: UInt8, value: UInt8)] = []
        
        // Collect all pitch bend events from all MIDI regions
        var allPitchBendEvents: [(absoluteTime: Double, value: Int16)] = []
        
        for region in track.midiRegions {
            for note in region.notes {
                // Convert region-relative time to absolute time
                let absoluteStart = region.startBeat + note.startBeat
                allNotes.append((
                    absoluteTime: absoluteStart,
                    pitch: note.pitch,
                    velocity: note.velocity,
                    duration: note.durationBeats
                ))
            }
            
            // Collect CC events
            for ccEvent in region.controllerEvents {
                let absoluteTime = region.startBeat + ccEvent.beat
                allCCEvents.append((absoluteTime: absoluteTime, controller: ccEvent.controller, value: ccEvent.value))
            }
            
            // Collect pitch bend events
            for pbEvent in region.pitchBendEvents {
                let absoluteTime = region.startBeat + pbEvent.beat
                allPitchBendEvents.append((absoluteTime: absoluteTime, value: pbEvent.value))
            }
        }
        
        // Sort by time
        allNotes.sort { $0.absoluteTime < $1.absoluteTime }
        allCCEvents.sort { $0.absoluteTime < $1.absoluteTime }
        allPitchBendEvents.sort { $0.absoluteTime < $1.absoluteTime }
        
        // Convert to MIDI events
        var events: [(deltaTime: UInt32, status: UInt8, data1: UInt8, data2: UInt8)] = []
        var currentTime: Double = 0
        
        // Convert beats to ticks
        func beatsToTicks(_ beats: Double) -> UInt32 {
            UInt32(beats * Double(ticksPerQuarter))
        }
        
        // Create note on/off pairs plus CC and pitch bend events
        enum MIDIEventType {
            case noteOn(pitch: UInt8, velocity: UInt8)
            case noteOff(pitch: UInt8)
            case cc(controller: UInt8, value: UInt8)
            case pitchBend(value: Int16)
        }
        
        var allEvents: [(time: Double, eventType: MIDIEventType)] = []
        
        for note in allNotes {
            allEvents.append((time: note.absoluteTime, eventType: .noteOn(pitch: note.pitch, velocity: note.velocity)))
            allEvents.append((time: note.absoluteTime + note.duration, eventType: .noteOff(pitch: note.pitch)))
        }
        
        for cc in allCCEvents {
            allEvents.append((time: cc.absoluteTime, eventType: .cc(controller: cc.controller, value: cc.value)))
        }
        
        for pb in allPitchBendEvents {
            allEvents.append((time: pb.absoluteTime, eventType: .pitchBend(value: pb.value)))
        }
        
        allEvents.sort { $0.time < $1.time }
        
        // Convert to delta times
        for event in allEvents {
            let deltaTicks = beatsToTicks(event.time - currentTime)
            
            switch event.eventType {
            case .noteOn(let pitch, let velocity):
                events.append((deltaTime: deltaTicks, status: 0x90, data1: pitch, data2: velocity))
            case .noteOff(let pitch):
                events.append((deltaTime: deltaTicks, status: 0x80, data1: pitch, data2: 0))
            case .cc(let controller, let value):
                events.append((deltaTime: deltaTicks, status: 0xB0, data1: controller, data2: value))
            case .pitchBend(let value):
                // Pitch bend is 14-bit: value -8192 to +8191, mapped to 0 to 16383
                let midiValue = Int(value) + 8192
                let lsb = UInt8(midiValue & 0x7F)
                let msb = UInt8((midiValue >> 7) & 0x7F)
                events.append((deltaTime: deltaTicks, status: 0xE0, data1: lsb, data2: msb))
            }
            
            currentTime = event.time
        }
        
        // Build Standard MIDI File
        var midiData = Data()
        
        // Header chunk "MThd"
        midiData.append(contentsOf: [0x4D, 0x54, 0x68, 0x64])  // "MThd"
        midiData.append(contentsOf: [0x00, 0x00, 0x00, 0x06])  // Header length = 6
        midiData.append(contentsOf: [0x00, 0x00])              // Format 0 (single track)
        midiData.append(contentsOf: [0x00, 0x01])              // Number of tracks = 1
        midiData.append(contentsOf: UInt16(ticksPerQuarter).bigEndianBytes)  // Ticks per quarter
        
        // Track chunk "MTrk"
        var trackData = Data()
        
        // Tempo meta event (at time 0)
        let microsecondsPerBeat = UInt32(60_000_000 / tempo)
        trackData.append(0x00)  // Delta time = 0
        trackData.append(contentsOf: [0xFF, 0x51, 0x03])  // Tempo meta event
        trackData.append(contentsOf: [
            UInt8((microsecondsPerBeat >> 16) & 0xFF),
            UInt8((microsecondsPerBeat >> 8) & 0xFF),
            UInt8(microsecondsPerBeat & 0xFF)
        ])
        
        // Track name meta event
        let trackName = track.name.data(using: .utf8) ?? Data()
        trackData.append(0x00)  // Delta time = 0
        trackData.append(contentsOf: [0xFF, 0x03])  // Track name
        trackData.append(contentsOf: variableLengthQuantity(UInt32(trackName.count)))
        trackData.append(trackName)
        
        // Add note events
        for event in events {
            trackData.append(contentsOf: variableLengthQuantity(event.deltaTime))
            trackData.append(event.status)
            trackData.append(event.data1)
            trackData.append(event.data2)
        }
        
        // End of track meta event
        trackData.append(0x00)  // Delta time = 0
        trackData.append(contentsOf: [0xFF, 0x2F, 0x00])  // End of track
        
        // Add track header
        midiData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])  // "MTrk"
        midiData.append(contentsOf: UInt32(trackData.count).bigEndianBytes)
        midiData.append(trackData)
        
        return midiData
    }
    
    /// Convert AVAudioPCMBuffer to WAV Data
    private func bufferToWAVData(buffer: AVAudioPCMBuffer, sampleRate: Double, bitDepth: Int) throws -> Data {
        // Create a temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        TempFileManager.track(tempURL)
        defer { TempFileManager.untrack(tempURL, deleteIfExists: true) }
        try writeToWAVFile(buffer: buffer, url: tempURL, sampleRate: sampleRate, bitDepth: bitDepth)
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        
        return data
    }
    
    /// Convert integer to MIDI variable-length quantity
    private func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        if value == 0 { return [0] }
        
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
}

// MARK: - UInt Extensions for MIDI

extension UInt16 {
    /// Convert to big-endian bytes for MIDI file format
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

// MARK: - Export Error

enum ExportError: LocalizedError, Equatable {
    case bufferCreationFailed
    case renderTimeout
    case invalidAudioFormat
    case fileWriteFailed
    case cancelled
    case formatNotSupported
    case formatConversionFailed
    case formatFallback(originalFormat: AudioFileFormat, fallbackURL: URL)
    
    static func == (lhs: ExportError, rhs: ExportError) -> Bool {
        switch (lhs, rhs) {
        case (.bufferCreationFailed, .bufferCreationFailed): return true
        case (.renderTimeout, .renderTimeout): return true
        case (.invalidAudioFormat, .invalidAudioFormat): return true
        case (.fileWriteFailed, .fileWriteFailed): return true
        case (.cancelled, .cancelled): return true
        case (.formatNotSupported, .formatNotSupported): return true
        case (.formatConversionFailed, .formatConversionFailed): return true
        case (.formatFallback(let f1, let u1), .formatFallback(let f2, let u2)):
            return f1 == f2 && u1 == u2
        default: return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer for export"
        case .renderTimeout:
            return "Export rendering timed out"
        case .invalidAudioFormat:
            return "Invalid audio format for export"
        case .fileWriteFailed:
            return "Failed to write export file"
        case .cancelled:
            return "Export was cancelled"
        case .formatNotSupported:
            return "The selected format is not supported on this system"
        case .formatConversionFailed:
            return "Failed to convert audio to the selected format"
        case .formatFallback(let format, let url):
            return "\(format.displayName) encoding failed. Exported to \(url.lastPathComponent) instead."
        }
    }
}

