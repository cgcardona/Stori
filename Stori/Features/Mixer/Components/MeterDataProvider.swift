//
//  MeterDataProvider.swift
//  Stori
//
//  Real-time audio meter data provider for mixer visualization
//

import SwiftUI
import Combine
import Observation

// MARK: - Meter Data Provider
// PERFORMANCE: Using @Observable for fine-grained updates
// Only views reading specific meter data re-render when that data changes
@Observable
class MeterDataProvider {
    private(set) var trackMeters: [UUID: ChannelMeterData] = [:]
    private(set) var masterMeterData = ChannelMeterData()
    
    @ObservationIgnored
    private var audioEngine: AudioEngine?
    @ObservationIgnored
    private weak var projectManager: ProjectManager?
    @ObservationIgnored
    private var displayLink: CVDisplayLink?
    @ObservationIgnored
    private var isMonitoring = false
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored
    private var updateTimer: Timer?
    
    // Peak hold decay
    @ObservationIgnored
    private var peakHoldTimers: [UUID: Date] = [:]
    @ObservationIgnored
    private let peakHoldDuration: TimeInterval = 3.0
    
    // Update throttling
    // PERFORMANCE: 15 FPS is visually smooth and reduces CPU by 50% vs 30 FPS
    // Professional DAWs typically run meters at 15-20 FPS
    @ObservationIgnored
    private var lastUpdateTime: Date = Date()
    @ObservationIgnored
    private let updateInterval: TimeInterval = 1.0 / 15.0  // 15 FPS (was 30 FPS)
    
    // PERFORMANCE: Idle detection - pause timer when all levels are zero
    @ObservationIgnored
    private var consecutiveZeroFrames: Int = 0
    @ObservationIgnored
    private let idleThreshold: Int = 30  // Pause after ~2 seconds of silence (30 frames at 15 FPS)
    @ObservationIgnored
    private var isIdle: Bool = false
    
    deinit {
        // Synchronous cleanup of timer and monitoring state.
        stopMonitoring()
    }
    
    // MARK: - Public Interface
    
    func meterData(for trackId: UUID) -> ChannelMeterData {
        trackMeters[trackId] ?? .zero
    }
    
    func startMonitoring(audioEngine: AudioEngine, projectManager: ProjectManager) {
        guard !isMonitoring else { return }
        
        self.audioEngine = audioEngine
        self.projectManager = projectManager
        isMonitoring = true
        
        // Start update timer (can be invalidated cleanly)
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        updateTimer?.invalidate()
        updateTimer = nil
        cancellables.removeAll()
        trackMeters.removeAll()
        masterMeterData = .zero
    }
    
    // MARK: - Meter Updates
    
    private func updateMeters() {
        guard isMonitoring, let audioEngine = audioEngine else { return }
        
        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now
        
        // Get current project tracks (read from ProjectManager for reactive updates)
        guard let project = projectManager?.currentProject else { return }
        
        // PERFORMANCE: Check if audio is playing or has activity
        let isPlaying = audioEngine.transportState.isPlaying
        let hasAudioActivity = audioEngine.masterLevelLeft > 0.001 || audioEngine.masterLevelRight > 0.001
        
        if !isPlaying && !hasAudioActivity {
            consecutiveZeroFrames += 1
            
            // After 2 seconds of silence, reduce to 2 FPS updates (just for decay visualization)
            if consecutiveZeroFrames >= idleThreshold {
                isIdle = true
                // Only update every 8 frames (roughly 2 FPS when idle)
                if consecutiveZeroFrames % 8 != 0 {
                    return
                }
            }
        } else {
            // Reset when there's activity
            consecutiveZeroFrames = 0
            isIdle = false
        }
        
        // Update track meters
        for track in project.tracks {
            updateTrackMeter(trackId: track.id)
        }
        
        // Update master meter
        updateMasterMeter()
        
        // Decay peaks (only if not fully idle)
        if !isIdle || consecutiveZeroFrames % 8 == 0 {
            decayPeaks()
        }
    }
    
    private func updateTrackMeter(trackId: UUID) {
        guard let audioEngine = audioEngine else { return }
        
        var meterData = trackMeters[trackId] ?? .zero
        var hasChanged = false
        
        // Get actual meter data from track node
        if let trackNode = audioEngine.getTrackNode(for: trackId) {
            // Read stereo levels from the track node (already calculated in audio tap)
            let leftLevel = trackNode.currentLevelLeft
            let rightLevel = trackNode.currentLevelRight
            
            // Apply smoothing for visual appeal
            let smoothing: Float = 0.3
            let newLeftLevel = meterData.leftLevel * (1 - smoothing) + leftLevel * smoothing
            let newRightLevel = meterData.rightLevel * (1 - smoothing) + rightLevel * smoothing
            
            // OPTIMIZATION: Only update if level changed by more than threshold
            // This prevents constant re-renders when levels are near-zero
            let threshold: Float = 0.001
            if abs(newLeftLevel - meterData.leftLevel) > threshold || 
               abs(newRightLevel - meterData.rightLevel) > threshold {
                meterData.leftLevel = newLeftLevel
                meterData.rightLevel = newRightLevel
                hasChanged = true
            }
            
            // Update peaks from track node
            let peakLeft = trackNode.peakLevelLeft
            let peakRight = trackNode.peakLevelRight
            
            if peakLeft > meterData.peakLeft {
                meterData.peakLeft = peakLeft
                peakHoldTimers[trackId] = Date()
                hasChanged = true
            }
            if peakRight > meterData.peakRight {
                meterData.peakRight = peakRight
                peakHoldTimers[trackId] = Date()
                hasChanged = true
            }
            
            // Clipping detection (>= 1.0 means clipping)
            if (peakLeft >= 1.0 || peakRight >= 1.0) && !meterData.isClipping {
                meterData.isClipping = true
                hasChanged = true
            }
        } else {
            // No track node - decay levels
            let newLeftLevel = max(0, meterData.leftLevel * 0.85)
            let newRightLevel = max(0, meterData.rightLevel * 0.85)
            
            // Only update if there's meaningful change
            if meterData.leftLevel > 0.001 || meterData.rightLevel > 0.001 {
                meterData.leftLevel = newLeftLevel
                meterData.rightLevel = newRightLevel
                hasChanged = true
            }
        }
        
        // OPTIMIZATION: Only update dictionary (triggering SwiftUI) if values changed
        if hasChanged {
            trackMeters[trackId] = meterData
        }
    }
    
    private func updateMasterMeter() {
        guard let audioEngine = audioEngine else { return }
        
        // Read actual master levels from AudioEngine
        let leftLevel = audioEngine.masterLevelLeft
        let rightLevel = audioEngine.masterLevelRight
        let peakLeft = audioEngine.masterPeakLeft
        let peakRight = audioEngine.masterPeakRight
        
        // Apply smoothing for visual appeal
        let smoothing: Float = 0.3
        let newLeftLevel = masterMeterData.leftLevel * (1 - smoothing) + leftLevel * smoothing
        let newRightLevel = masterMeterData.rightLevel * (1 - smoothing) + rightLevel * smoothing
        
        // OPTIMIZATION: Only update if level changed by more than threshold
        let threshold: Float = 0.001
        var hasChanged = false
        
        if abs(newLeftLevel - masterMeterData.leftLevel) > threshold || 
           abs(newRightLevel - masterMeterData.rightLevel) > threshold {
            masterMeterData.leftLevel = newLeftLevel
            masterMeterData.rightLevel = newRightLevel
            hasChanged = true
        }
        
        // Update peaks
        if peakLeft > masterMeterData.peakLeft {
            masterMeterData.peakLeft = peakLeft
            hasChanged = true
        }
        if peakRight > masterMeterData.peakRight {
            masterMeterData.peakRight = peakRight
            hasChanged = true
        }
        
        // Clipping detection (Issue #73): Use AudioEngine's real-time safe clip detection
        // This uses the 0.999 threshold and latching behavior from MeteringService
        let isClipping = audioEngine.isClipping
        if isClipping != masterMeterData.isClipping {
            masterMeterData.isClipping = isClipping
            hasChanged = true
        }
        
        // Update LUFS loudness values (only if changed)
        if abs(masterMeterData.loudnessMomentary - audioEngine.loudnessMomentary) > 0.1 {
            masterMeterData.loudnessMomentary = audioEngine.loudnessMomentary
            hasChanged = true
        }
        if abs(masterMeterData.loudnessShortTerm - audioEngine.loudnessShortTerm) > 0.1 {
            masterMeterData.loudnessShortTerm = audioEngine.loudnessShortTerm
            hasChanged = true
        }
        if abs(masterMeterData.loudnessIntegrated - audioEngine.loudnessIntegrated) > 0.1 {
            masterMeterData.loudnessIntegrated = audioEngine.loudnessIntegrated
            hasChanged = true
        }
        if abs(masterMeterData.truePeak - audioEngine.truePeak) > 0.1 {
            masterMeterData.truePeak = audioEngine.truePeak
            hasChanged = true
        }
        
        // Note: masterMeterData is a struct, and SwiftUI observes the whole object.
        // The struct mutation above will trigger updates only if we modified values.
        // If hasChanged is false, we haven't modified the struct at all.
        _ = hasChanged // Suppress unused variable warning
    }
    
    private func decayPeaks() {
        let now = Date()
        
        // Decay track peaks
        for (trackId, holdTime) in peakHoldTimers {
            if now.timeIntervalSince(holdTime) >= peakHoldDuration {
                if var meter = trackMeters[trackId] {
                    let newPeakLeft = max(meter.leftLevel, meter.peakLeft - 0.02)
                    let newPeakRight = max(meter.rightLevel, meter.peakRight - 0.02)
                    
                    // PERFORMANCE: Only update if there's meaningful change
                    if abs(newPeakLeft - meter.peakLeft) > 0.001 || abs(newPeakRight - meter.peakRight) > 0.001 {
                        meter.peakLeft = newPeakLeft
                        meter.peakRight = newPeakRight
                        trackMeters[trackId] = meter
                    }
                }
            }
        }
        
        // PERFORMANCE: Only decay master peaks if there's meaningful change
        let newMasterPeakLeft = max(masterMeterData.leftLevel, masterMeterData.peakLeft - 0.01)
        let newMasterPeakRight = max(masterMeterData.rightLevel, masterMeterData.peakRight - 0.01)
        
        if abs(newMasterPeakLeft - masterMeterData.peakLeft) > 0.001 {
            masterMeterData.peakLeft = newMasterPeakLeft
        }
        if abs(newMasterPeakRight - masterMeterData.peakRight) > 0.001 {
            masterMeterData.peakRight = newMasterPeakRight
        }
    }
    
    // MARK: - Reset
    
    func resetClipIndicator(for trackId: UUID) {
        if var meter = trackMeters[trackId] {
            meter.isClipping = false
            trackMeters[trackId] = meter
        }
    }
    
    func resetMasterClipIndicator() {
        // Reset both MeteringService and UI state (Issue #73)
        audioEngine?.resetClipIndicator()
        masterMeterData.isClipping = false
    }
    
    func resetAllPeaks() {
        for trackId in trackMeters.keys {
            if var meter = trackMeters[trackId] {
                meter.peakLeft = 0
                meter.peakRight = 0
                meter.isClipping = false
                trackMeters[trackId] = meter
            }
        }
        masterMeterData.peakLeft = 0
        masterMeterData.peakRight = 0
        masterMeterData.isClipping = false
    }
}
