//
//  AutomationRecorder.swift
//  Stori
//
//  Records parameter changes during playback for automation capture.
//  Supports Touch, Latch, and Write modes with automatic point thinning.
//

import Foundation
import Observation

// MARK: - Automation Recorder

/// Records parameter changes during playback and commits them to track automation lanes.
/// Handles Touch/Latch/Write mode behaviors and point thinning.
@MainActor
@Observable
class AutomationRecorder {
    
    // MARK: - Observable State
    
    /// Whether any recording is currently active
    private(set) var isRecording: Bool = false
    
    /// Active recordings by track ID
    private(set) var activeRecordings: [UUID: ActiveRecording] = [:]
    
    // MARK: - Dependencies
    
    @ObservationIgnored
    private weak var audioEngine: AudioEngine?
    
    // MARK: - Types
    
    /// An active recording session for a parameter
    struct ActiveRecording {
        let trackId: UUID
        let parameter: AutomationParameter
        var capturedPoints: [AutomationPoint]
        let startBeat: Double
        let previousValue: Float?  // For Touch mode - value to return to
        let curveType: CurveType
        
        init(
            trackId: UUID,
            parameter: AutomationParameter,
            startBeat: Double,
            previousValue: Float?,
            curveType: CurveType = .linear
        ) {
            self.trackId = trackId
            self.parameter = parameter
            self.capturedPoints = []
            self.startBeat = startBeat
            self.previousValue = previousValue
            self.curveType = curveType
        }
    }
    
    // MARK: - Configuration
    
    /// Minimum time between captured points (seconds)
    @ObservationIgnored
    private let captureInterval: TimeInterval = 1.0 / 60.0  // 60fps capture rate
    
    /// Threshold for point thinning (normalized value difference)
    @ObservationIgnored
    private let thinningThreshold: Float = 0.005  // 0.5% change required
    
    /// Last capture beat per recording (to throttle captures)
    @ObservationIgnored
    private var lastCaptureBeat: [UUID: Double] = [:]
    
    // MARK: - Initialization
    
    init() {}

    
    /// Configure the recorder with the audio engine
    func configure(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }
    
    // MARK: - Recording Control
    
    /// Start recording automation for a parameter on a track
    /// - Parameters:
    ///   - trackId: The track to record automation for
    ///   - parameter: The parameter being automated
    ///   - initialValue: The current value when recording starts
    ///   - curveType: The curve type to use for recorded points
    func startRecording(
        trackId: UUID,
        parameter: AutomationParameter,
        initialValue: Float,
        curveType: CurveType = .linear
    ) {
        guard let engine = audioEngine else { return }
        
        // Only record during playback
        guard engine.transportState.isPlaying else { return }
        
        let currentBeat = engine.currentPosition.beats
        
        // Get existing value at this beat (for Touch mode return)
        let existingValue = getExistingValue(
            trackId: trackId,
            parameter: parameter,
            atBeat: currentBeat
        )
        
        let recording = ActiveRecording(
            trackId: trackId,
            parameter: parameter,
            startBeat: currentBeat,
            previousValue: existingValue,
            curveType: curveType
        )
        
        // Use a composite key for track+parameter
        let key = recordingKey(trackId: trackId, parameter: parameter)
        activeRecordings[key] = recording
        lastCaptureBeat[key] = currentBeat
        isRecording = true
        
        // Capture the initial point
        capturePoint(value: initialValue, for: key)
    }
    
    /// Capture a value during recording
    /// - Parameters:
    ///   - value: The current parameter value (0-1 normalized)
    ///   - trackId: The track being recorded
    ///   - parameter: The parameter being recorded
    func captureValue(_ value: Float, for trackId: UUID, parameter: AutomationParameter) {
        let key = recordingKey(trackId: trackId, parameter: parameter)
        guard activeRecordings[key] != nil else { return }
        
        // Throttle captures to captureInterval (converted to beats at current tempo)
        guard let engine = audioEngine else { return }
        let currentBeat = engine.currentPosition.beats
        let tempo = engine.currentProject?.tempo ?? 120.0
        let captureIntervalBeats = captureInterval * (tempo / 60.0)
        
        if let lastBeat = lastCaptureBeat[key],
           currentBeat - lastBeat < captureIntervalBeats {
            return
        }
        
        lastCaptureBeat[key] = currentBeat
        capturePoint(value: value, for: key)
    }
    
    /// Stop recording and commit automation
    /// - Parameters:
    ///   - trackId: The track to stop recording for
    ///   - parameter: The parameter to stop recording
    ///   - mode: The automation mode (affects how data is committed)
    ///   - commitHandler: Callback to commit the automation to the project
    func stopRecording(
        trackId: UUID,
        parameter: AutomationParameter,
        mode: AutomationMode,
        commitHandler: @escaping ([AutomationPoint], AutomationParameter, UUID) -> Void
    ) {
        let key = recordingKey(trackId: trackId, parameter: parameter)
        guard var recording = activeRecordings[key] else { return }
        
        // Add final point at current position
        if let engine = audioEngine {
            let currentBeat = engine.currentPosition.beats
            let tempo = engine.currentProject?.tempo ?? 120.0
            let captureIntervalBeats = captureInterval * (tempo / 60.0)
            
            if let lastPoint = recording.capturedPoints.last {
                // Only add if we've moved in beats
                if currentBeat > lastPoint.beat + captureIntervalBeats {
                    let finalPoint = AutomationPoint(
                        beat: currentBeat,
                        value: lastPoint.value,
                        curve: recording.curveType
                    )
                    recording.capturedPoints.append(finalPoint)
                }
            }
            
            // For Touch mode, add a return point
            if mode == .touch, let previousValue = recording.previousValue {
                let returnBeat = currentBeat + 0.05 * (tempo / 60.0)  // Small delay for smooth return
                let returnPoint = AutomationPoint(
                    beat: returnBeat,
                    value: previousValue,
                    curve: .smooth
                )
                recording.capturedPoints.append(returnPoint)
            }
        }
        
        // Apply point thinning
        let thinnedPoints = thinPoints(recording.capturedPoints)
        
        // Commit if we have meaningful data
        if !thinnedPoints.isEmpty {
            commitHandler(thinnedPoints, parameter, trackId)
        }
        
        // Clean up
        activeRecordings.removeValue(forKey: key)
        lastCaptureBeat.removeValue(forKey: key)
        isRecording = !activeRecordings.isEmpty
    }
    
    /// Cancel recording without committing
    func cancelRecording(trackId: UUID, parameter: AutomationParameter) {
        let key = recordingKey(trackId: trackId, parameter: parameter)
        activeRecordings.removeValue(forKey: key)
        lastCaptureBeat.removeValue(forKey: key)
        isRecording = !activeRecordings.isEmpty
    }
    
    /// Cancel all active recordings
    func cancelAllRecordings() {
        activeRecordings.removeAll()
        lastCaptureBeat.removeAll()
        isRecording = false
    }
    
    // MARK: - Private Helpers
    
    /// Generate a unique key for track+parameter combination
    private func recordingKey(trackId: UUID, parameter: AutomationParameter) -> UUID {
        // Use a deterministic UUID based on track and parameter
        // This is a simple approach - could use a proper composite key
        let combined = "\(trackId.uuidString)-\(parameter.rawValue)"
        return UUID(uuidString: String(combined.prefix(36))) ?? trackId
    }
    
    /// Capture a single point
    private func capturePoint(value: Float, for key: UUID) {
        guard var recording = activeRecordings[key],
              let engine = audioEngine else { return }
        
        let currentBeat = engine.currentPosition.beats
        let point = AutomationPoint(
            beat: currentBeat,
            value: max(0, min(1, value)),
            curve: recording.curveType
        )
        
        recording.capturedPoints.append(point)
        activeRecordings[key] = recording
    }
    
    /// Get existing automation value at a beat
    private func getExistingValue(
        trackId: UUID,
        parameter: AutomationParameter,
        atBeat beat: Double
    ) -> Float? {
        // This would query the existing automation lanes (stored in beats)
        // For now, return nil (will be connected to project data)
        return nil
    }
    
    /// Apply Douglas-Peucker-like thinning to reduce point count
    /// Keeps points where the value changes significantly
    private func thinPoints(_ points: [AutomationPoint]) -> [AutomationPoint] {
        guard points.count > 2 else { return points }
        
        var result: [AutomationPoint] = []
        result.append(points[0])  // Always keep first
        
        var lastKept = points[0]
        
        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            
            // Keep point if value changed significantly
            let valueDiff = abs(current.value - lastKept.value)
            if valueDiff >= thinningThreshold {
                result.append(current)
                lastKept = current
            }
            // Keep point if direction changes (local min/max)
            else if i > 0 {
                let prev = points[i - 1]
                let wasRising = current.value > prev.value
                let willFall = next.value < current.value
                let wasFlat = abs(current.value - prev.value) < 0.001
                
                if (wasRising && willFall) || (!wasRising && !willFall && !wasFlat) {
                    result.append(current)
                    lastKept = current
                }
            }
        }
        
        result.append(points[points.count - 1])  // Always keep last
        
        return result
    }
    
    // MARK: - Query State
    
    /// Check if recording is active for a specific parameter
    func isRecording(trackId: UUID, parameter: AutomationParameter) -> Bool {
        let key = recordingKey(trackId: trackId, parameter: parameter)
        return activeRecordings[key] != nil
    }
    
    /// Get captured point count for a recording
    func capturedPointCount(trackId: UUID, parameter: AutomationParameter) -> Int {
        let key = recordingKey(trackId: trackId, parameter: parameter)
        return activeRecordings[key]?.capturedPoints.count ?? 0
    }
    
    // MARK: - Cleanup
}

// MARK: - Automation Commit Helper

extension AutomationRecorder {
    
    /// Helper to merge recorded points into an existing automation lane
    static func mergePoints(
        recorded: [AutomationPoint],
        into existing: inout [AutomationPoint],
        startBeat: Double,
        endBeat: Double,
        mode: AutomationMode
    ) {
        switch mode {
        case .off, .read:
            // These modes don't record
            break
            
        case .touch, .latch:
            // Replace points in the recorded beat range, keep others
            existing.removeAll { point in
                point.beat >= startBeat && point.beat <= endBeat
            }
            existing.append(contentsOf: recorded)
            existing.sort { $0.beat < $1.beat }
            
        case .write:
            // Replace ALL existing points with recorded
            // (In a full implementation, this would clear from playback start)
            existing.removeAll { point in
                point.beat >= startBeat
            }
            existing.append(contentsOf: recorded)
            existing.sort { $0.beat < $1.beat }
        }
    }
}
