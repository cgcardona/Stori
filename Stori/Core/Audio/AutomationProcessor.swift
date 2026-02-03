//
//  AutomationProcessor.swift
//  Stori
//
//  Real-time automation processor for applying parameter automation during playback.
//  Designed for efficiency with O(log n) value lookup using binary search.
//
//  ARCHITECTURE: Beats-First
//  - All automation points are stored and looked up in beats (musical time)
//  - This matches the DAW's beats-first architecture
//
//  THREADING MODEL:
//  - AutomationProcessor: Thread-safe data store (os_unfair_lock protected)
//  - AutomationEngine: Dedicated high-priority queue for applying values
//  - TrackAudioNode: Receives values via thread-safe property setters
//

import Foundation
import AVFoundation
import os.lock

// MARK: - Automation Curve Constants

/// Constants for automation curve calculations
enum AutomationCurveConstants {
    /// Exponent for exponential curve (determines acceleration)
    /// 2.5 gives a professional "slow start, fast finish" feel
    static let exponentialPower: Float = 2.5
    
    /// Exponent for logarithmic curve (inverse of exponential)
    static let logarithmicPower: Float = 2.5
    
    /// Steepness of S-curve sigmoid function
    /// 10 gives a pronounced S with ~10% tails
    static let sigmoidSteepness: Double = 10.0
}

// MARK: - Automation Engine

/// High-priority engine for applying automation values during playback.
/// Runs on a dedicated queue, separate from UI updates.
///
/// ARCHITECTURE:
/// - Fires at 120Hz (8.3ms) for smooth parameter updates
/// - Reads beat position atomically from transport
/// - Applies values directly to track nodes (thread-safe)
/// - Uses AutomationProcessor for value lookups (O(log n))
final class AutomationEngine: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Update frequency in Hz (120Hz = 8.3ms, smoother than 60Hz)
    private let updateFrequency: Double = 120.0
    
    /// Timer interval in seconds
    private var timerInterval: Double { 1.0 / updateFrequency }
    
    // MARK: - State
    
    private var stateLock = os_unfair_lock_s()
    private var _isRunning = false
    
    var isRunning: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isRunning
    }
    
    // MARK: - Dependencies
    
    /// Provider for current beat position (thread-safe)
    var beatPositionProvider: (() -> Double)?
    
    /// Provider for tempo (use when only tempo is needed)
    var tempoProvider: (() -> Double)?
    
    /// Provider for unified scheduling context (use when multiple timing values needed)
    /// Takes precedence over tempoProvider when both are set
    var schedulingContextProvider: (() -> AudioSchedulingContext)?
    
    /// Callback to apply automation values (receives raw values; engine merges with mixer fallback for nil)
    var applyValuesHandler: ((UUID, AutomationValues) -> Void)?
    
    /// Provider for track IDs that need automation
    var trackIdsProvider: (() -> [UUID])?
    
    /// Reference to the automation processor
    weak var processor: AutomationProcessor?
    
    /// Get current tempo, preferring schedulingContextProvider if available
    private var currentTempo: Double {
        if let contextProvider = schedulingContextProvider {
            return contextProvider().tempo
        }
        return tempoProvider?() ?? 120.0
    }
    
    // MARK: - Timer
    
    /// Dedicated high-priority queue for automation
    private let automationQueue = DispatchQueue(
        label: "com.stori.automation",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    
    /// High-precision timer for automation updates
    private var timer: DispatchSourceTimer?
    
    // MARK: - Lifecycle
    
    func start() {
        os_unfair_lock_lock(&stateLock)
        guard !_isRunning else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        _isRunning = true
        os_unfair_lock_unlock(&stateLock)
        
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: automationQueue)
        timer.schedule(
            deadline: .now(),
            repeating: timerInterval,
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.processAutomation()
        }
        timer.resume()
        self.timer = timer
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        
        os_unfair_lock_lock(&stateLock)
        _isRunning = false
        os_unfair_lock_unlock(&stateLock)
    }
    
    // MARK: - Processing
    
    private func processAutomation() {
        guard let currentBeat = beatPositionProvider?(),
              let trackIds = trackIdsProvider?(),
              let processor = processor else { return }
        
        // PERFORMANCE: Single lock acquisition for all tracks via batch read
        // This reduces lock contention from O(n) to O(1) acquisitions per update
        let allValues = processor.getAllValuesForTracks(trackIds, atBeat: currentBeat)
        
        // Apply values outside the lock (TrackAudioNode setters are thread-safe)
        for (trackId, values) in allValues {
            applyValuesHandler?(trackId, values)
        }
    }
}

// MARK: - Automation Processor

/// Processes automation data and provides real-time parameter values during playback.
/// Uses efficient data structures for fast lookup during the audio render path.
/// All positions are in BEATS (musical time), not seconds.
final class AutomationProcessor: @unchecked Sendable {
    
    // MARK: - Types
    
    /// Pre-computed curve data for fast real-time lookup
    struct AutomationCurve {
        /// Automation points sorted by beat position
        let points: [(beat: Double, value: Float, curve: CurveType)]
        let defaultValue: Float
        /// Value before first point (deterministic WYSIWYG when set)
        let initialValue: Float?
        
        /// Get interpolated value at a specific beat using binary search
        /// O(log n) complexity for real-time safety
        /// Returns initialValue or first point's value for positions before the first point (deterministic playback)
        func value(atBeat beat: Double) -> Float? {
            guard !points.isEmpty else { return nil }
            
            // Binary search to find the surrounding points
            var low = 0
            var high = points.count - 1
            
            // Before first point: use stored initialValue or first point (deterministic, not current mixer)
            if beat < points[0].beat {
                return initialValue ?? points[0].value
            }
            
            // After last point - return last point's value (stay at final level)
            if beat >= points[high].beat {
                return points[high].value
            }
            
            // Binary search for the interval containing beat
            while low < high - 1 {
                let mid = (low + high) / 2
                if points[mid].beat <= beat {
                    low = mid
                } else {
                    high = mid
                }
            }
            
            // Interpolate between points[low] and points[high]
            let p1 = points[low]
            let p2 = points[high]
            
            return interpolate(from: p1, to: p2, atBeat: beat)
        }
        
        /// Interpolate between two points based on curve type
        private func interpolate(
            from p1: (beat: Double, value: Float, curve: CurveType),
            to p2: (beat: Double, value: Float, curve: CurveType),
            atBeat beat: Double
        ) -> Float {
            let duration = p2.beat - p1.beat
            guard duration > 0 else { return p1.value }
            
            let t = Float((beat - p1.beat) / duration)
            
            let delta = p2.value - p1.value
            
            switch p1.curve {
            case .linear:
                return p1.value + delta * t
            case .smooth:
                // Smooth (ease in-out) using smootherstep: 6t^5 - 15t^4 + 10t^3
                let smoothT = t * t * t * (t * (t * 6 - 15) + 10)
                return p1.value + delta * smoothT
            case .step:
                return p1.value
            case .exponential:
                // Slow start, fast finish (power curve)
                let expT = pow(t, AutomationCurveConstants.exponentialPower)
                return p1.value + delta * expT
            case .logarithmic:
                // Fast start, slow finish (inverse power curve)
                let logT = 1 - pow(1 - t, AutomationCurveConstants.logarithmicPower)
                return p1.value + delta * logT
            case .sCurve:
                // S-curve using sigmoid function: 1 / (1 + e^(-k*(t-0.5)))
                let sigmoid = 1.0 / (1.0 + exp(-AutomationCurveConstants.sigmoidSteepness * (Double(t) - 0.5)))
                return p1.value + delta * Float(sigmoid)
            }
        }
    }
    
    /// Snapshot of all automation for a single track
    struct TrackAutomationSnapshot {
        var volume: AutomationCurve?
        var pan: AutomationCurve?
        var eqLow: AutomationCurve?
        var eqMid: AutomationCurve?
        var eqHigh: AutomationCurve?
        var mode: AutomationMode
        
        init(mode: AutomationMode = .read) {
            self.mode = mode
        }
    }
    
    // MARK: - Properties
    
    /// Track automation snapshots - keyed by track ID
    /// Uses lock for thread-safe access from audio thread
    private var trackSnapshots: [UUID: TrackAutomationSnapshot] = [:]
    private var snapshotLock = os_unfair_lock_s()
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Data Management (Main Thread)
    
    /// Update automation data for a track (called from main thread when project changes)
    func updateAutomation(for trackId: UUID, lanes: [AutomationLane], mode: AutomationMode) {
        var snapshot = TrackAutomationSnapshot(mode: mode)
        
        // Build curves for each parameter (visibility only affects UI, not playback)
        for lane in lanes where !lane.points.isEmpty {
            let sortedPoints = lane.sortedPoints.map { point in
                (beat: point.beat, value: point.value, curve: point.curve)
            }
            let curve = AutomationCurve(points: sortedPoints, defaultValue: lane.parameter.defaultValue, initialValue: lane.initialValue)
            
            switch lane.parameter {
            case .volume:
                snapshot.volume = curve
            case .pan:
                snapshot.pan = curve
            case .eqLow:
                snapshot.eqLow = curve
            case .eqMid:
                snapshot.eqMid = curve
            case .eqHigh:
                snapshot.eqHigh = curve
            default:
                // Other parameters can be added as needed
                break
            }
        }
        
        // Thread-safe update
        os_unfair_lock_lock(&snapshotLock)
        trackSnapshots[trackId] = snapshot
        os_unfair_lock_unlock(&snapshotLock)
    }
    
    /// Remove automation data for a track
    func removeAutomation(for trackId: UUID) {
        os_unfair_lock_lock(&snapshotLock)
        trackSnapshots.removeValue(forKey: trackId)
        os_unfair_lock_unlock(&snapshotLock)
    }
    
    /// Clear all automation data
    func clearAll() {
        os_unfair_lock_lock(&snapshotLock)
        trackSnapshots.removeAll()
        os_unfair_lock_unlock(&snapshotLock)
    }
    
    // MARK: - Value Lookup (Audio Thread Safe, Beats-First)
    
    /// Get automation mode for a track
    func getMode(for trackId: UUID) -> AutomationMode? {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        return trackSnapshots[trackId]?.mode
    }
    
    /// Get volume automation value at beat position (returns nil if no automation)
    func getVolume(for trackId: UUID, atBeat beat: Double) -> Float? {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        guard let snapshot = trackSnapshots[trackId],
              snapshot.mode.canRead,
              let curve = snapshot.volume else {
            return nil
        }
        return curve.value(atBeat: beat)
    }
    
    /// Get pan automation value at beat position (returns nil if no automation)
    func getPan(for trackId: UUID, atBeat beat: Double) -> Float? {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        guard let snapshot = trackSnapshots[trackId],
              snapshot.mode.canRead,
              let curve = snapshot.pan else {
            return nil
        }
        return curve.value(atBeat: beat)
    }
    
    /// Get EQ automation values at beat position
    func getEQ(for trackId: UUID, atBeat beat: Double) -> (low: Float?, mid: Float?, high: Float?) {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        guard let snapshot = trackSnapshots[trackId],
              snapshot.mode.canRead else {
            return (nil, nil, nil)
        }
        
        return (
            low: snapshot.eqLow?.value(atBeat: beat),
            mid: snapshot.eqMid?.value(atBeat: beat),
            high: snapshot.eqHigh?.value(atBeat: beat)
        )
    }
    
    /// Get all automatable values for a track at a specific beat position
    /// Returns a struct with optional values for each parameter
    func getAllValues(for trackId: UUID, atBeat beat: Double) -> AutomationValues? {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        guard let snapshot = trackSnapshots[trackId],
              snapshot.mode.canRead else {
            return nil
        }
        
        return AutomationValues(
            volume: snapshot.volume?.value(atBeat: beat),
            pan: snapshot.pan?.value(atBeat: beat),
            eqLow: snapshot.eqLow?.value(atBeat: beat),
            eqMid: snapshot.eqMid?.value(atBeat: beat),
            eqHigh: snapshot.eqHigh?.value(atBeat: beat)
        )
    }
    
    /// Check if a track has any active automation
    func hasAutomation(for trackId: UUID) -> Bool {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        guard let snapshot = trackSnapshots[trackId] else { return false }
        return snapshot.volume != nil || snapshot.pan != nil ||
               snapshot.eqLow != nil || snapshot.eqMid != nil || snapshot.eqHigh != nil
    }
    
    // MARK: - Batch Value Lookup (Single Lock Acquisition)
    
    /// Get all automation values for multiple tracks at once with a single lock acquisition.
    /// This dramatically reduces lock contention when processing many tracks.
    /// Returns a dictionary of trackId -> AutomationValues (nil values omitted)
    func getAllValuesForTracks(_ trackIds: [UUID], atBeat beat: Double) -> [UUID: AutomationValues] {
        os_unfair_lock_lock(&snapshotLock)
        defer { os_unfair_lock_unlock(&snapshotLock) }
        
        var results: [UUID: AutomationValues] = [:]
        results.reserveCapacity(trackIds.count)
        
        for trackId in trackIds {
            guard let snapshot = trackSnapshots[trackId],
                  snapshot.mode.canRead else {
                continue
            }
            
            let values = AutomationValues(
                volume: snapshot.volume?.value(atBeat: beat),
                pan: snapshot.pan?.value(atBeat: beat),
                eqLow: snapshot.eqLow?.value(atBeat: beat),
                eqMid: snapshot.eqMid?.value(atBeat: beat),
                eqHigh: snapshot.eqHigh?.value(atBeat: beat)
            )
            // Include every canRead track so engine can apply mixer fallback for nil params (avoids pops when adding first point)
            results[trackId] = values
        }
        
        return results
    }
}

// MARK: - Automation Values

/// Container for all automation values at a point in time
struct AutomationValues {
    let volume: Float?
    let pan: Float?
    let eqLow: Float?
    let eqMid: Float?
    let eqHigh: Float?
    
    /// Check if any values are present
    var hasAnyValue: Bool {
        volume != nil || pan != nil || eqLow != nil || eqMid != nil || eqHigh != nil
    }
}
