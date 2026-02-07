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
/// # Sample-Accurate Automation Architecture
///
/// ## Playback (120Hz Real-Time)
/// - AutomationEngine fires at 120Hz (8.3ms intervals) for smooth parameter updates
/// - Reads beat position atomically from TransportController
/// - Applies values directly to TrackAudioNode setters (thread-safe, with adaptive smoothing)
/// - Uses AutomationProcessor for O(log n) binary search value lookups
/// - Prevents zipper noise with adaptive smoothing based on rate of change
///
/// ## Export (120Hz Offline)
/// - ProjectExportService applies automation at same 120Hz frequency
/// - Uses identical AutomationProcessor for value calculation
/// - Converts samples → seconds → beats using project tempo
/// - Applies to AVAudioMixerNode parameters directly
/// - Ensures WYHIWYG: export matches playback exactly
///
/// ## Why 120Hz?
/// - 8.3ms update interval is smooth enough for most automation curves
/// - Faster than typical 60Hz (16.7ms) for professional-grade automation
/// - Matches industry standard for automation resolution
/// - Balances CPU efficiency with smooth parameter changes
///
/// ## Smoothing Strategy
/// - TrackAudioNode applies adaptive smoothing on top of 120Hz updates
/// - Large jumps (> 0.2): Minimal smoothing (step-like behavior)
/// - Medium changes: Light smoothing (linear curves)
/// - Small changes: Heavy smoothing (zipper prevention)
/// - This two-stage approach (120Hz + adaptive smoothing) provides professional results
///
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
    
    /// Cached track IDs to avoid allocation at 120Hz
    /// REAL-TIME SAFETY: Updated only when tracks change, not on every timer tick
    private var cachedTrackIds: [UUID] = []
    private var trackIdsCacheLock = os_unfair_lock_s()
    
    /// Thread-safe track node cache for the automation handler.
    /// Eliminates cross-thread access to @MainActor-isolated AudioEngine.trackNodes.
    /// Updated from MainActor when tracks change; read from automationQueue at 120Hz.
    private var trackNodeCacheLock = os_unfair_lock_s()
    private var cachedTrackNodes: [UUID: TrackAudioNode] = [:]
    private var cachedMixerDefaults: [UUID: (volume: Float, pan: Float)] = [:]
    
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
        
        // Drain the automation queue to ensure no in-flight handler is still
        // accessing track nodes. Without this barrier, a pending processAutomation()
        // call could access freed TrackAudioNodes after clearAllTracks() runs.
        automationQueue.sync {}
    }
    
    // MARK: - Track ID Cache Management
    
    /// Update the cached track IDs (call when tracks are added/removed)
    /// REAL-TIME SAFETY: This eliminates array allocation at 120Hz
    func updateTrackIds(_ ids: [UUID]) {
        os_unfair_lock_lock(&trackIdsCacheLock)
        cachedTrackIds = ids
        os_unfair_lock_unlock(&trackIdsCacheLock)
    }
    
    /// Get cached track IDs (thread-safe read)
    private func getCachedTrackIds() -> [UUID] {
        os_unfair_lock_lock(&trackIdsCacheLock)
        let ids = cachedTrackIds
        os_unfair_lock_unlock(&trackIdsCacheLock)
        return ids
    }
    
    // MARK: - Track Node Cache
    
    /// Update the thread-safe track node snapshot (call from MainActor when tracks change).
    /// The automation handler reads from this cache instead of accessing @MainActor state.
    func updateTrackNodeCache(_ nodes: [UUID: TrackAudioNode], mixerDefaults: [UUID: (volume: Float, pan: Float)]) {
        os_unfair_lock_lock(&trackNodeCacheLock)
        cachedTrackNodes = nodes
        cachedMixerDefaults = mixerDefaults
        os_unfair_lock_unlock(&trackNodeCacheLock)
    }
    
    /// Thread-safe lookup of a cached track node by ID
    func getCachedTrackNode(_ trackId: UUID) -> TrackAudioNode? {
        os_unfair_lock_lock(&trackNodeCacheLock)
        let node = cachedTrackNodes[trackId]
        os_unfair_lock_unlock(&trackNodeCacheLock)
        return node
    }
    
    /// Thread-safe lookup of cached mixer defaults (volume, pan) for fallback values
    func getCachedMixerDefaults(_ trackId: UUID) -> (volume: Float, pan: Float)? {
        os_unfair_lock_lock(&trackNodeCacheLock)
        let defaults = cachedMixerDefaults[trackId]
        os_unfair_lock_unlock(&trackNodeCacheLock)
        return defaults
    }
    
    // MARK: - Processing
    
    private func processAutomation() {
        // Bail early if stopped — prevents accessing freed track nodes
        // during project reload (stop() sets _isRunning = false before
        // draining this queue with a sync barrier).
        os_unfair_lock_lock(&stateLock)
        let running = _isRunning
        os_unfair_lock_unlock(&stateLock)
        guard running else { return }
        
        guard let currentBeat = beatPositionProvider?(),
              let processor = processor else { return }
        
        // REAL-TIME SAFETY: Use cached track IDs to avoid allocation at 120Hz
        // Only allocates when tracks change (via updateTrackIds), not on every timer tick
        let trackIds = getCachedTrackIds()
        guard !trackIds.isEmpty else { return }
        
        // PERFORMANCE: Single lock acquisition for all tracks via batch read
        // This reduces lock contention from O(n) to O(1) acquisitions per update
        let allValues = processor.getAllValuesForTracks(trackIds, atBeat: currentBeat)
        
        // Apply values outside the lock (TrackAudioNode setters are thread-safe)
        for (trackId, values) in allValues {
            applyValuesHandler?(trackId, values)
        }
    }
    
    deinit {
        // Cancel the automation processing timer to prevent retain cycle.
        timer?.cancel()
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
                // S-curve using normalized sigmoid function: 1 / (1 + e^(-k*(t-0.5)))
                // Normalize to 0→1 range by subtracting minimum and dividing by range
                let k = AutomationCurveConstants.sigmoidSteepness
                let sigmoid = 1.0 / (1.0 + exp(-k * (Double(t) - 0.5)))
                // Normalize: sigmoid(0) and sigmoid(1) are not exactly 0 and 1
                let sigmoid0 = 1.0 / (1.0 + exp(k * 0.5))  // Value at t=0
                let sigmoid1 = 1.0 / (1.0 + exp(-k * 0.5))  // Value at t=1
                let normalized = (sigmoid - sigmoid0) / (sigmoid1 - sigmoid0)
                return p1.value + delta * Float(normalized)
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
        // REAL-TIME SAFETY: Read snapshots inside lock (fast), build results outside lock
        // This eliminates dictionary insertion inside lock which can trigger reallocation
        
        // Step 1: Copy snapshots inside lock (minimal hold time)
        var snapshots: [UUID: TrackAutomationSnapshot] = [:]
        snapshots.reserveCapacity(trackIds.count)
        
        os_unfair_lock_lock(&snapshotLock)
        for trackId in trackIds {
            if let snapshot = trackSnapshots[trackId], snapshot.mode.canRead {
                snapshots[trackId] = snapshot
            }
        }
        os_unfair_lock_unlock(&snapshotLock)
        
        // Step 2: Build results OUTSIDE lock (allocation happens here, not during lock)
        var results: [UUID: AutomationValues] = [:]
        results.reserveCapacity(snapshots.count)
        
        for (trackId, snapshot) in snapshots {
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
    
    // MARK: - Cleanup
    
    /// Root cause: TaskLocal::StopLookupScope can bad-free when deinit runs off MainActor.
    /// Empty deinit ensures proper Swift Concurrency / TaskLocal cleanup order.
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
