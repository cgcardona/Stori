//
//  AutomationModels.swift
//  Stori
//
//  Core automation data models for professional automation.
//  Supports parameter automation with multiple curve types and recording modes.
//

import Foundation
import SwiftUI

// MARK: - Automation Mode

/// Professional automation modes for recording and playback
enum AutomationMode: String, Codable, CaseIterable {
    case off = "Off"
    case read = "Read"
    case touch = "Touch"
    case latch = "Latch"
    case write = "Write"
    
    var icon: String {
        switch self {
        case .off: return "rectangle.dashed"
        case .read: return "play.fill"
        case .touch: return "hand.point.up.fill"
        case .latch: return "pin.fill"
        case .write: return "pencil"
        }
    }
    
    var color: Color {
        switch self {
        case .off: return .secondary
        case .read: return .green
        case .touch: return .yellow
        case .latch: return .orange
        case .write: return .red
        }
    }
    
    var shortLabel: String {
        switch self {
        case .off: return "Off"
        case .read: return "R"
        case .touch: return "T"
        case .latch: return "L"
        case .write: return "W"
        }
    }
    
    var description: String {
        switch self {
        case .off: return "Automation disabled"
        case .read: return "Read: Follows existing automation"
        case .touch: return "Touch: Records while touching control, returns to previous"
        case .latch: return "Latch: Records while touching, stays at last value"
        case .write: return "Write: Overwrites all automation during playback"
        }
    }
    
    /// Whether this mode can record new automation
    var canRecord: Bool {
        switch self {
        case .off, .read: return false
        case .touch, .latch, .write: return true
        }
    }
    
    /// Whether this mode reads/plays back automation
    var canRead: Bool {
        switch self {
        case .off: return false
        case .read, .touch, .latch, .write: return true
        }
    }
}

// MARK: - Curve Type

/// Curve interpolation type between automation points.
/// Professional DAWs support various curve shapes for precise automation control.
enum CurveType: String, Codable, CaseIterable {
    case linear = "Linear"
    case smooth = "Smooth"
    case step = "Step"
    case exponential = "Exp"
    case logarithmic = "Log"
    case sCurve = "S-Curve"
    
    var icon: String {
        switch self {
        case .linear: return "line.diagonal"
        case .smooth: return "waveform.path"
        case .step: return "stairs"
        case .exponential: return "arrow.up.right"
        case .logarithmic: return "arrow.up.left"
        case .sCurve: return "s.circle"
        }
    }
    
    /// Description for UI tooltips
    var description: String {
        switch self {
        case .linear: return "Straight line between points"
        case .smooth: return "Smooth ease in-out curve"
        case .step: return "Hold value until next point"
        case .exponential: return "Slow start, fast end"
        case .logarithmic: return "Fast start, slow end"
        case .sCurve: return "S-shaped curve with tension"
        }
    }
}

// MARK: - Bezier Control Point

/// Control point for Bezier curve shaping.
/// Each automation point can have optional control points for precise curve adjustment.
struct BezierControlPoint: Codable, Equatable {
    /// Horizontal offset from the automation point (in beats)
    var beatOffset: Double
    
    /// Vertical offset from the automation point (normalized 0-1 range)
    var valueOffset: Float
    
    init(beatOffset: Double = 0, valueOffset: Float = 0) {
        self.beatOffset = beatOffset
        self.valueOffset = valueOffset
    }
    
    /// Calculate the absolute position given a reference point
    func absolutePosition(from point: (beat: Double, value: Float)) -> (beat: Double, value: Float) {
        return (
            beat: point.beat + beatOffset,
            value: max(0, min(1, point.value + valueOffset))
        )
    }
}

// MARK: - Automation Point

/// Single point in an automation curve with optional Bezier control.
/// Supports both simple curve types and advanced Bezier curve shaping.
struct AutomationPoint: Identifiable, Codable, Equatable {
    let id: UUID
    var beat: Double            // Position in beats (musical time, NOT seconds)
    var value: Float            // 0-1 normalized value
    var curve: CurveType        // Interpolation to next point
    
    // MARK: - Advanced Curve Control
    
    /// Tension value for curve shaping (-1 to 1).
    /// 0 = standard curve, negative = more linear, positive = more curved
    var tension: Float
    
    /// Optional outgoing Bezier control point (for cubic Bezier curves)
    var controlPointOut: BezierControlPoint?
    
    /// Optional incoming Bezier control point (from previous point)
    var controlPointIn: BezierControlPoint?
    
    init(
        id: UUID = UUID(),
        beat: Double,
        value: Float,
        curve: CurveType = .linear,
        tension: Float = 0,
        controlPointOut: BezierControlPoint? = nil,
        controlPointIn: BezierControlPoint? = nil
    ) {
        self.id = id
        self.beat = beat
        self.value = max(0, min(1, value))
        self.curve = curve
        self.tension = max(-1, min(1, tension))
        self.controlPointOut = controlPointOut
        self.controlPointIn = controlPointIn
    }
    
    /// Whether this point uses Bezier curve control
    var usesBezier: Bool {
        controlPointOut != nil || controlPointIn != nil
    }
}

// MARK: - Automation Parameter

/// Automatable parameter types
enum AutomationParameter: String, Codable, CaseIterable, Hashable {
    // Core mixer parameters
    case volume = "Volume"
    case pan = "Pan"
    
    // EQ bands
    case eqLow = "EQ Low"
    case eqMid = "EQ Mid"
    case eqHigh = "EQ High"
    
    // MIDI CC parameters
    case midiCC1 = "Mod Wheel (CC1)"
    case midiCC7 = "Volume (CC7)"
    case midiCC10 = "Pan (CC10)"
    case midiCC11 = "Expression (CC11)"
    case midiCC64 = "Sustain (CC64)"
    case midiCC74 = "Filter Cutoff (CC74)"
    
    // Pitch
    case pitchBend = "Pitch Bend"
    
    // Synth parameters
    case synthCutoff = "Synth Cutoff"
    case synthResonance = "Synth Resonance"
    case synthAttack = "Synth Attack"
    case synthRelease = "Synth Release"
    
    /// MIDI CC number for MIDI-based parameters
    var ccNumber: UInt8? {
        switch self {
        case .midiCC1: return 1
        case .midiCC7: return 7
        case .midiCC10: return 10
        case .midiCC11: return 11
        case .midiCC64: return 64
        case .midiCC74: return 74
        default: return nil
        }
    }
    
    /// Default value for this parameter (0-1 normalized)
    var defaultValue: Float {
        switch self {
        case .volume: return 0.8
        case .pan: return 0.5  // Center
        case .eqLow, .eqMid, .eqHigh: return 0.5  // 0 dB
        case .midiCC1, .midiCC11: return 0
        case .midiCC7: return 1.0
        case .midiCC10: return 0.5
        case .midiCC64: return 0
        case .midiCC74: return 1.0
        case .pitchBend: return 0.5  // Center
        case .synthCutoff: return 1.0
        case .synthResonance: return 0
        case .synthAttack: return 0.1
        case .synthRelease: return 0.3
        }
    }
    
    /// SF Symbol icon for this parameter
    var icon: String {
        switch self {
        case .volume: return "speaker.wave.2"
        case .pan: return "arrow.left.and.right"
        case .eqLow: return "waveform.badge.minus"
        case .eqMid: return "waveform"
        case .eqHigh: return "waveform.badge.plus"
        case .pitchBend: return "waveform.path.ecg"
        case .synthCutoff, .midiCC74: return "dial.low"
        case .synthResonance: return "dial.high"
        case .synthAttack, .synthRelease: return "chart.line.uptrend.xyaxis"
        default: return "slider.horizontal.3"
        }
    }
    
    /// Short name for compact display in lanes
    var shortName: String {
        switch self {
        case .volume: return "Vol"
        case .pan: return "Pan"
        case .eqLow: return "EQ-L"
        case .eqMid: return "EQ-M"
        case .eqHigh: return "EQ-H"
        case .midiCC1: return "Mod"
        case .midiCC7: return "Vol"
        case .midiCC10: return "Pan"
        case .midiCC11: return "Expr"
        case .midiCC64: return "Sus"
        case .midiCC74: return "Cut"
        case .pitchBend: return "Bend"
        case .synthCutoff: return "Cut"
        case .synthResonance: return "Res"
        case .synthAttack: return "Atk"
        case .synthRelease: return "Rel"
        }
    }
    
    /// Color for this parameter's automation lane
    var color: Color {
        switch self {
        case .volume: return .blue
        case .pan: return .green
        case .eqLow: return Color(red: 0.57, green: 0.25, blue: 0.05)  // Brown
        case .eqMid: return .yellow
        case .eqHigh: return .orange
        case .pitchBend: return .purple
        case .midiCC74, .synthCutoff: return .orange
        case .synthResonance: return .pink
        default: return .gray
        }
    }
    
    /// Whether this is a core mixer parameter (volume, pan, EQ)
    var isMixerParameter: Bool {
        switch self {
        case .volume, .pan, .eqLow, .eqMid, .eqHigh:
            return true
        default:
            return false
        }
    }
    
    /// All mixer-related parameters for the "Add Lane" menu
    static var mixerParameters: [AutomationParameter] {
        [.volume, .pan, .eqLow, .eqMid, .eqHigh]
    }
    
    /// All MIDI CC parameters
    static var midiCCParameters: [AutomationParameter] {
        [.midiCC1, .midiCC7, .midiCC10, .midiCC11, .midiCC64, .midiCC74]
    }
    
    /// All synth parameters
    static var synthParameters: [AutomationParameter] {
        [.synthCutoff, .synthResonance, .synthAttack, .synthRelease]
    }
}

// MARK: - Automation Lane

/// Represents an automation lane for a specific parameter
struct AutomationLane: Identifiable, Codable, Equatable {
    let id: UUID
    var parameter: AutomationParameter
    var points: [AutomationPoint]
    /// Value used for playback before the first automation point (deterministic WYSIWYG).
    /// When nil, playback uses the first point's value for positions before it.
    var initialValue: Float?
    var isVisible: Bool
    var isLocked: Bool
    var colorHex: String
    private(set) var height: CGFloat  // Validated height to prevent UI issues
    
    /// SwiftUI Color accessor (uses Color extension from EditableTrackColor.swift)
    var color: Color {
        get { Color(hex: colorHex) ?? .orange }
        set { colorHex = newValue.toHex() }
    }
    
    init(
        id: UUID = UUID(),
        parameter: AutomationParameter = .volume,
        points: [AutomationPoint] = [],
        initialValue: Float? = nil,
        isVisible: Bool = true,
        isLocked: Bool = false,
        color: Color = .orange,
        height: CGFloat = 60
    ) {
        self.id = id
        self.parameter = parameter
        // Ensure points are sorted on initialization (for deserialization)
        self.points = points.sorted { $0.beat < $1.beat }
        self.initialValue = initialValue
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.colorHex = color.toHex()
        // Clamp height to reasonable range (40-500) to prevent UI issues
        self.height = max(40, min(500, height))
    }
    
    /// Update the lane height with validation
    mutating func setHeight(_ newHeight: CGFloat) {
        // Clamp to reasonable range: minimum 40pt, maximum 500pt
        self.height = max(40, min(500, newHeight))
    }
    
    /// Points sorted by beat position for efficient lookup.
    /// Points are now always kept sorted, so this just returns the array directly.
    var sortedPoints: [AutomationPoint] {
        points
    }
    
    /// Get interpolated value at a specific beat position
    func value(atBeat beat: Double) -> Float {
        guard !points.isEmpty else { return initialValue ?? parameter.defaultValue }
        
        let sorted = sortedPoints
        
        // Before first point: use initialValue (deterministic) or first point's value
        guard let first = sorted.first else { return parameter.defaultValue }
        if beat < first.beat { return initialValue ?? first.value }
        if beat == first.beat { return first.value }
        
        // After last point
        guard let last = sorted.last else { return parameter.defaultValue }
        if beat >= last.beat { return last.value }
        
        // Find surrounding points and interpolate
        for i in 0..<(sorted.count - 1) {
            let p1 = sorted[i]
            let p2 = sorted[i + 1]
            
            if beat >= p1.beat && beat < p2.beat {
                return interpolate(from: p1, to: p2, atBeat: beat)
            }
        }
        
        return parameter.defaultValue
    }
    
    /// Interpolate between two points based on curve type and optional Bezier control.
    /// Supports standard curves, tension adjustment, and cubic Bezier curves.
    private func interpolate(from p1: AutomationPoint, to p2: AutomationPoint, atBeat beat: Double) -> Float {
        let t = Float((beat - p1.beat) / (p2.beat - p1.beat))
        let delta = p2.value - p1.value
        
        // Check for Bezier control points first
        if p1.usesBezier || p2.usesBezier {
            return interpolateBezier(from: p1, to: p2, t: t)
        }
        
        // Apply tension adjustment to t
        let adjustedT = applyTension(t: t, tension: p1.tension)
        
        switch p1.curve {
        case .linear:
            return p1.value + delta * adjustedT
            
        case .smooth:
            // Smooth (ease in-out) using improved smootherstep
            let smoothT = adjustedT * adjustedT * adjustedT * (adjustedT * (adjustedT * 6 - 15) + 10)
            return p1.value + delta * smoothT
            
        case .step:
            return p1.value
            
        case .exponential:
            // Exponential ease-in (slow start, fast end)
            let expT = pow(adjustedT, 2.5)
            return p1.value + delta * expT
            
        case .logarithmic:
            // Logarithmic ease-out (fast start, slow end)
            let logT = 1 - pow(1 - adjustedT, 2.5)
            return p1.value + delta * logT
            
        case .sCurve:
            // Pronounced S-curve with adjustable tension
            let tensionFactor: Double = Double(1 + abs(p1.tension) * 2)
            let tCentered: Double = Double(adjustedT) - 0.5
            let exponent: Double = -tensionFactor * tCentered * 10
            let sT: Double = 1.0 / (1.0 + exp(exponent))
            return p1.value + delta * Float(sT)
        }
    }
    
    /// Apply tension adjustment to the interpolation parameter
    private func applyTension(t: Float, tension: Float) -> Float {
        if tension == 0 { return t }
        
        if tension > 0 {
            // Positive tension: more curved (ease in-out)
            let power = 1 + tension * 2
            if t < 0.5 {
                return pow(2 * t, power) / 2
            } else {
                return 1 - pow(2 * (1 - t), power) / 2
            }
        } else {
            // Negative tension: more linear (closer to step)
            let blend = 1 + tension  // tension is negative, so this reduces curve
            let linear = t
            let curved = t * t * (3 - 2 * t)
            return linear * (1 - blend) + curved * blend
        }
    }
    
    /// Cubic Bezier interpolation for smooth professional-grade curves
    private func interpolateBezier(from p1: AutomationPoint, to p2: AutomationPoint, t: Float) -> Float {
        // Get control points (default to smooth curve if not specified)
        let beatDelta = p2.beat - p1.beat
        let valueDelta = p2.value - p1.value
        
        // Calculate control point positions
        let cp1 = p1.controlPointOut ?? BezierControlPoint(
            beatOffset: beatDelta * 0.33,
            valueOffset: 0
        )
        let cp2 = p2.controlPointIn ?? BezierControlPoint(
            beatOffset: -beatDelta * 0.33,
            valueOffset: 0
        )
        
        // Absolute control point values
        let c1Value = p1.value + cp1.valueOffset
        let c2Value = p2.value + cp2.valueOffset
        
        // Cubic Bezier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
        let oneMinusT = 1 - t
        let oneMinusT2 = oneMinusT * oneMinusT
        let oneMinusT3 = oneMinusT2 * oneMinusT
        let t2 = t * t
        let t3 = t2 * t
        
        let value = oneMinusT3 * p1.value +
                    3 * oneMinusT2 * t * c1Value +
                    3 * oneMinusT * t2 * c2Value +
                    t3 * p2.value
        
        return max(0, min(1, value))
    }
    
    // MARK: - Point Management
    
    /// Add a new point at the specified beat and value.
    /// Points are inserted in sorted order for optimal performance during playback.
    mutating func addPoint(atBeat beat: Double, value: Float, curve: CurveType = .linear) {
        let point = AutomationPoint(beat: beat, value: value, curve: curve)
        
        // Binary search for insertion point to maintain sorted order
        let insertIndex = points.firstIndex { $0.beat > beat } ?? points.count
        points.insert(point, at: insertIndex)
    }
    
    /// Remove point by ID
    mutating func removePoint(_ id: UUID) {
        points.removeAll { $0.id == id }
    }
    
    /// Update a point's beat position and value.
    /// If beat position changes, the point is re-inserted to maintain sorted order.
    mutating func updatePoint(_ id: UUID, beat: Double? = nil, value: Float? = nil) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        
        // If beat changes, remove and re-insert to maintain sorted order
        if let newBeat = beat {
            let point = points[index]
            var updatedPoint = point
            updatedPoint.beat = max(0, newBeat)
            if let newValue = value {
                updatedPoint.value = max(0, min(1, newValue))
            }
            
            // Remove old point and re-insert in sorted position
            points.remove(at: index)
            let insertIndex = points.firstIndex { $0.beat > updatedPoint.beat } ?? points.count
            points.insert(updatedPoint, at: insertIndex)
        } else if let newValue = value {
            // Only value changed, no need to re-sort
            points[index].value = max(0, min(1, newValue))
        }
    }
    
    /// Clear all points
    mutating func clearPoints() {
        points.removeAll()
    }
}

// MARK: - Automation Data Container

/// Container for all automation data on a track (used for serialization and management)
struct TrackAutomationData: Codable, Equatable {
    var lanes: [AutomationLane]
    var mode: AutomationMode
    var isExpanded: Bool  // UI state: whether automation lanes are visible in timeline
    
    init(
        lanes: [AutomationLane] = [],
        mode: AutomationMode = .read,
        isExpanded: Bool = false
    ) {
        self.lanes = lanes
        self.mode = mode
        self.isExpanded = isExpanded
    }
    
    /// Get lane for a specific parameter
    func lane(for parameter: AutomationParameter) -> AutomationLane? {
        lanes.first { $0.parameter == parameter }
    }
    
    /// Get value for a parameter at a specific beat position
    func value(for parameter: AutomationParameter, atBeat beat: Double) -> Float? {
        guard mode.canRead else { return nil }
        return lane(for: parameter)?.value(atBeat: beat)
    }
    
    /// Add a new lane for a parameter
    mutating func addLane(for parameter: AutomationParameter) {
        guard !lanes.contains(where: { $0.parameter == parameter }) else { return }
        let lane = AutomationLane(parameter: parameter, color: parameter.color)
        lanes.append(lane)
    }
    
    /// Remove lane for a parameter
    mutating func removeLane(for parameter: AutomationParameter) {
        lanes.removeAll { $0.parameter == parameter }
    }
}

// MARK: - AudioTrack Mixer Value (Deterministic Automation)

extension AudioTrack {
    /// Returns the current mixer value (0–1) for an automation parameter.
    /// Used when creating new automation lanes so playback before the first point uses this snapshot (deterministic WYSIWYG).
    func mixerValue(for parameter: AutomationParameter) -> Float {
        let m = mixerSettings
        switch parameter {
        case .volume: return m.volume
        case .pan: return m.pan
        case .eqLow: return max(0, min(1, (m.lowEQ / 24) + 0.5))
        case .eqMid: return max(0, min(1, (m.midEQ / 24) + 0.5))
        case .eqHigh: return max(0, min(1, (m.highEQ / 24) + 0.5))
        default: return parameter.defaultValue
        }
    }
}
