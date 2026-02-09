//
//  VirtualKeyboardView.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Virtual MIDI Keyboard - Play software instruments with your computer keyboard
//  Virtual keyboard for playing instruments with computer keyboard (Musical Typing).
//
//  LATENCY COMPENSATION:
//  - Uses NSEvent.timestamp (hardware timestamps) for sub-millisecond accuracy
//  - Calculates actual latency dynamically by comparing hardware time vs current time
//  - Falls back to fixed 30ms compensation when hardware timestamp unavailable
//  - Notes are timestamped with negative compensation to align with user intent
//  - Audio feedback is immediate (no latency), only recording timestamps are adjusted
//  - Compensation is tempo-aware: converted from seconds to beats for musical accuracy
//
//  Keyboard Layout:
//  Black keys: W E   T Y U   O P
//  White keys: A S D F G H J K L ; '
//
//  Controls:
//  Z - Octave Down    X - Octave Up
//  C - Velocity Down  V - Velocity Up
//

import SwiftUI
import Combine
import Observation
import AVFoundation
import AppKit

// MARK: - Virtual Keyboard View

struct VirtualKeyboardView: View {
    @State private var keyboardState = VirtualKeyboardState()
    @Environment(AudioEngine.self) private var audioEngine
    /// Close action — works for both overlay and sheet presentation
    var onClose: (() -> Void)?
    
    /// Use shared InstrumentManager for routing
    private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            Divider()
            
            // Track routing indicator
            trackRoutingIndicator
            
            Divider()
            
            // Controls row
            controlsRow
            
            Divider()
            
            // Piano keyboard
            pianoKeyboard
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            
            // Key mapping legend
            keyMappingLegend
        }
        .frame(width: 720, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Configure keyboard state with audio engine for tempo-aware latency compensation
            keyboardState.configure(audioEngine: audioEngine)
            keyboardState.startListening()
        }
        .onDisappear {
            keyboardState.stopListening()
        }
    }
    
    // MARK: - Track Routing Indicator
    
    private var trackRoutingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(instrumentManager.hasActiveInstrument ? .green : .orange)
            
            if let trackName = instrumentManager.activeTrackName,
               let trackColor = instrumentManager.activeTrackColor {
                HStack(spacing: 6) {
                    Circle()
                        .fill(trackColor)
                        .frame(width: 10, height: 10)
                    Text("Playing to: \(trackName)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("No MIDI track selected – using standalone synth")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Activity indicator
            if keyboardState.pressedNotes.count > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(1.2)
                        .animation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true), value: keyboardState.pressedNotes.count)
                    Text("\(keyboardState.pressedNotes.count) notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Latency Compensation Badge
    
    private var latencyCompensationBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Latency: \(String(format: "%.0f", keyboardState.currentLatencyMs))ms (\(String(format: "%.3f", keyboardState.currentLatencyBeats)) beats @ \(String(format: "%.0f", keyboardState.currentTempo)) BPM)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(6)
        .accessibilityIdentifier("virtualKeyboard.latencyBadge")
        .help("Compensating for UI event latency to ensure accurate MIDI recording timestamps")
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack {
            Image(systemName: "pianokeys")
                .font(.title2)
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            
            Text("Virtual Keyboard")
                .font(.headline)
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(keyboardState.isSynthReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(keyboardState.isSynthReady ? "Ready" : "Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Latency compensation indicator
            latencyCompensationBadge
            
            // Keyboard shortcut hint
            Text("⌘⇧K")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            
            Button("Close") {
                onClose?()
            }
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Controls Row
    
    private var controlsRow: some View {
        HStack(spacing: 24) {
            // Octave control
            HStack(spacing: 8) {
                Text("Octave")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { keyboardState.octaveDown() }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("z", modifiers: [])
                .disabled(keyboardState.octave <= 0)
                
                Text("C\(keyboardState.octave)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .frame(width: 32)
                
                Button(action: { keyboardState.octaveUp() }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("x", modifiers: [])
                .disabled(keyboardState.octave >= 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Velocity control
            HStack(spacing: 8) {
                Text("Velocity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { keyboardState.velocityDown() }) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [])
                .disabled(keyboardState.velocity <= 1)
                
                Text("\(keyboardState.velocity)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .frame(width: 40)
                
                // Velocity meter
                VelocityMeter(velocity: keyboardState.velocity)
                    .frame(width: 60, height: 16)
                
                Button(action: { keyboardState.velocityUp() }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("v", modifiers: [])
                .disabled(keyboardState.velocity >= 127)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
            
            // Sustain pedal toggle
            Toggle(isOn: Binding(
                get: { keyboardState.sustainEnabled },
                set: { newValue in
                    keyboardState.setSustain(newValue)
                }
            )) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.bottomhalf.filled")
                    Text("Sustain")
                        .font(.caption)
                }
            }
            .toggleStyle(.button)
            .keyboardShortcut(" ", modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Piano Keyboard
    
    private var pianoKeyboard: some View {
        GeometryReader { geometry in
            let whiteKeyWidth = geometry.size.width / 14 // 14 white keys (2 octaves)
            let whiteKeyHeight = geometry.size.height
            let blackKeyWidth = whiteKeyWidth * 0.6
            let blackKeyHeight = whiteKeyHeight * 0.6
            
            ZStack(alignment: .topLeading) {
                // White keys
                HStack(spacing: 2) {
                    ForEach(keyboardState.whiteKeys, id: \.pitch) { key in
                        WhiteKeyView(
                            key: key,
                            isPressed: keyboardState.pressedNotes.contains(key.pitch),
                            width: whiteKeyWidth - 2,
                            height: whiteKeyHeight,
                            onPress: { timestamp in keyboardState.noteOn(key.pitch, hardwareTimestamp: timestamp) },
                            onRelease: { timestamp in keyboardState.noteOff(key.pitch, hardwareTimestamp: timestamp) }
                        )
                    }
                }
                
                // Black keys (positioned over white keys)
                ForEach(keyboardState.blackKeys, id: \.pitch) { key in
                    BlackKeyView(
                        key: key,
                        isPressed: keyboardState.pressedNotes.contains(key.pitch),
                        width: blackKeyWidth,
                        height: blackKeyHeight,
                        onPress: { timestamp in keyboardState.noteOn(key.pitch, hardwareTimestamp: timestamp) },
                        onRelease: { timestamp in keyboardState.noteOff(key.pitch, hardwareTimestamp: timestamp) }
                    )
                    .offset(x: blackKeyOffset(for: key, whiteKeyWidth: whiteKeyWidth))
                }
            }
        }
    }
    
    private func blackKeyOffset(for key: VirtualKey, whiteKeyWidth: CGFloat) -> CGFloat {
        // Calculate position based on which white key this black key is between
        let noteInOctave = Int(key.pitch) % 12
        let octaveOffset = CGFloat(Int(key.pitch) / 12 - keyboardState.octave) * 7 * whiteKeyWidth
        
        let positions: [Int: CGFloat] = [
            1: 0.7,   // C#
            3: 1.7,   // D#
            6: 3.7,   // F#
            8: 4.7,   // G#
            10: 5.7   // A#
        ]
        
        if let pos = positions[noteInOctave] {
            return octaveOffset + pos * whiteKeyWidth
        }
        return 0
    }
    
    // MARK: - Key Mapping Legend
    
    private var keyMappingLegend: some View {
        VStack(spacing: 4) {
            Divider()
            
            HStack(spacing: 24) {
                legendItem("A-L ; '", "White keys")
                legendItem("W E T Y U O P", "Black keys")
                legendItem("Z / X", "Octave ±")
                legendItem("C / V", "Velocity ±")
                legendItem("Space", "Sustain")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        }
    }
    
    private func legendItem(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            Text(description)
        }
    }
}

// MARK: - Velocity Meter

struct VelocityMeter: View {
    let velocity: UInt8
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlBackgroundColor))
                
                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(velocityColor)
                    .frame(width: geometry.size.width * CGFloat(velocity) / 127)
            }
        }
    }
    
    private var velocityColor: Color {
        if velocity < 40 {
            return .green
        } else if velocity < 80 {
            return .yellow
        } else if velocity < 110 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - White Key View

struct WhiteKeyView: View {
    let key: VirtualKey
    let isPressed: Bool
    let width: CGFloat
    let height: CGFloat
    let onPress: (TimeInterval?) -> Void
    let onRelease: (TimeInterval?) -> Void
    
    @State private var isHovered = false
    @State private var pressedByMouse = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Mouse event capture layer (transparent, captures clicks with timestamps)
            MouseEventCapturingView(
                onMouseDown: { timestamp in
                    pressedByMouse = true
                    onPress(timestamp)
                },
                onMouseUp: { timestamp in
                    if pressedByMouse {
                        pressedByMouse = false
                        onRelease(timestamp)
                    }
                }
            )
            .allowsHitTesting(true)
            
            // Key shape
            RoundedRectangle(cornerRadius: 4)
                .fill(isPressed ? Color.blue.opacity(0.3) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: isPressed ? 0 : 2, y: isPressed ? 0 : 2)
                .allowsHitTesting(false) // Let mouse events pass through to capture layer
            
            // Key label
            VStack(spacing: 2) {
                if let keyChar = key.keyboardKey {
                    Text(String(keyChar).uppercased())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                
                Text(key.noteName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            .allowsHitTesting(false) // Let mouse events pass through to capture layer
        }
        .frame(width: width, height: height)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Black Key View

struct BlackKeyView: View {
    let key: VirtualKey
    let isPressed: Bool
    let width: CGFloat
    let height: CGFloat
    let onPress: (TimeInterval?) -> Void
    let onRelease: (TimeInterval?) -> Void
    
    @State private var pressedByMouse = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Mouse event capture layer (transparent, captures clicks with timestamps)
            MouseEventCapturingView(
                onMouseDown: { timestamp in
                    pressedByMouse = true
                    onPress(timestamp)
                },
                onMouseUp: { timestamp in
                    if pressedByMouse {
                        pressedByMouse = false
                        onRelease(timestamp)
                    }
                }
            )
            .allowsHitTesting(true)
            
            // Key shape
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: isPressed ? [Color.blue.opacity(0.6), Color.blue.opacity(0.4)] : [Color.black, Color.gray.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: isPressed ? 0 : 2, y: isPressed ? 0 : 2)
                .allowsHitTesting(false) // Let mouse events pass through to capture layer
            
            // Key label
            if let keyChar = key.keyboardKey {
                Text(String(keyChar).uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Mouse Event Capturing View

/// Custom view that captures mouse events with hardware timestamps
/// Used for piano keys to get sub-millisecond click timing accuracy
struct MouseEventCapturingView: NSViewRepresentable {
    let onMouseDown: (TimeInterval) -> Void
    let onMouseUp: (TimeInterval) -> Void
    
    func makeNSView(context: Context) -> MouseEventView {
        let view = MouseEventView()
        view.onMouseDown = onMouseDown
        view.onMouseUp = onMouseUp
        return view
    }
    
    func updateNSView(_ nsView: MouseEventView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseUp = onMouseUp
    }
    
    class MouseEventView: NSView {
        var onMouseDown: ((TimeInterval) -> Void)?
        var onMouseUp: ((TimeInterval) -> Void)?
        
        override func mouseDown(with event: NSEvent) {
            onMouseDown?(event.timestamp)
            super.mouseDown(with: event)
        }
        
        override func mouseUp(with event: NSEvent) {
            onMouseUp?(event.timestamp)
            super.mouseUp(with: event)
        }
        
        override var acceptsFirstResponder: Bool { true }
    }
}

// MARK: - Virtual Key Model

struct VirtualKey {
    let pitch: UInt8
    let noteName: String
    let isBlackKey: Bool
    let keyboardKey: Character?
}

// MARK: - Virtual Keyboard State

@Observable
@MainActor
class VirtualKeyboardState {
    var octave: Int = 4
    var velocity: UInt8 = 100
    var sustainEnabled: Bool = false
    var pressedNotes: Set<UInt8> = []
    
    /// Notes being sustained by sustain pedal (but not currently pressed)
    @ObservationIgnored
    private var sustainedNotes: Set<UInt8> = []
    
    /// Fixed UI latency fallback (seconds) - used when hardware timestamp unavailable
    /// This represents the estimated delay between physical user action (click/keypress) and note trigger
    /// Typical values: 20-50ms depending on system load and event processing latency
    @ObservationIgnored
    private let fallbackLatencySeconds: TimeInterval = 0.030 // 30ms fallback
    
    /// Access to shared instrument manager
    @ObservationIgnored private var instrumentManager: InstrumentManager { InstrumentManager.shared }
    
    /// Access to audio engine for tempo information (needed for beat compensation calculation)
    @ObservationIgnored private weak var audioEngine: AudioEngine?
    
    /// Calculate latency compensation in beats from seconds
    /// - Parameter latencySeconds: Latency in seconds to convert
    /// - Returns: Latency in beats based on current tempo
    func latencySecondsToBeats(_ latencySeconds: TimeInterval) -> Double {
        // Get current tempo from audio engine (default to 120 BPM if not available)
        let tempo = audioEngine?.currentProject?.tempo ?? 120.0
        
        // Convert seconds to beats: beats = seconds * (BPM / 60)
        let beatsPerSecond = tempo / 60.0
        return latencySeconds * beatsPerSecond
    }
    
    // MARK: - Latency Compensation Visibility (for UI display)
    
    /// Current tempo from audio engine
    var currentTempo: Double {
        audioEngine?.currentProject?.tempo ?? 120.0
    }
    
    /// Current latency compensation in milliseconds
    var currentLatencyMs: Double {
        fallbackLatencySeconds * 1000.0
    }
    
    /// Current latency compensation in beats (dynamically updates with tempo)
    var currentLatencyBeats: Double {
        let tempo = audioEngine?.currentProject?.tempo ?? 120.0
        let beatsPerSecond = tempo / 60.0
        return fallbackLatencySeconds * beatsPerSecond
    }
    
    /// Calculate actual UI latency from hardware timestamp
    /// Uses NSEvent.timestamp (high-precision hardware time) vs CACurrentMediaTime()
    /// - Parameter hardwareTimestamp: NSEvent.timestamp from the event
    /// - Returns: Actual latency in seconds
    func calculateActualLatency(hardwareTimestamp: TimeInterval) -> TimeInterval {
        let currentTime = CACurrentMediaTime()
        // Actual latency = time now - time when user physically acted
        let actualLatency = currentTime - hardwareTimestamp
        
        // Clamp to reasonable range (0-100ms) to handle clock domain edge cases
        return max(0, min(actualLatency, 0.100))
    }
    
    /// Whether a track instrument is available
    var isSynthReady: Bool {
        instrumentManager.hasActiveInstrument
    }
    
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var keyUpMonitor: Any?
    
    // Keyboard mapping
    private let whiteKeyChars: [Character] = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"]
    private let blackKeyChars: [Character] = ["w", "e", "t", "y", "u", "o", "p"]
    
    // White key offsets from C (in semitones)
    private let whiteKeyOffsets: [Int] = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17]
    // Black key offsets from C (in semitones)  
    private let blackKeyOffsets: [Int] = [1, 3, 6, 8, 10, 13, 15]
    
    /// Whether we're routing to a track instrument
    var isRoutingToTrack: Bool {
        instrumentManager.hasActiveInstrument
    }
    
    var whiteKeys: [VirtualKey] {
        var keys: [VirtualKey] = []
        let basePitch = UInt8(octave * 12)
        
        // Generate 2 octaves of white keys
        for octaveNum in 0..<2 {
            for (index, offset) in [0, 2, 4, 5, 7, 9, 11].enumerated() {
                let pitch = basePitch + UInt8(octaveNum * 12 + offset)
                let keyIndex = octaveNum * 7 + index
                let keyChar: Character? = keyIndex < whiteKeyChars.count ? whiteKeyChars[keyIndex] : nil
                
                keys.append(VirtualKey(
                    pitch: pitch,
                    noteName: MIDIHelper.noteName(for: pitch),
                    isBlackKey: false,
                    keyboardKey: keyChar
                ))
            }
        }
        
        return keys
    }
    
    var blackKeys: [VirtualKey] {
        var keys: [VirtualKey] = []
        let basePitch = UInt8(octave * 12)
        
        // Generate 2 octaves of black keys
        for octaveNum in 0..<2 {
            for (index, offset) in [1, 3, 6, 8, 10].enumerated() {
                let pitch = basePitch + UInt8(octaveNum * 12 + offset)
                let keyIndex = octaveNum * 5 + index
                let keyChar: Character? = keyIndex < blackKeyChars.count ? blackKeyChars[keyIndex] : nil
                
                keys.append(VirtualKey(
                    pitch: pitch,
                    noteName: MIDIHelper.noteName(for: pitch),
                    isBlackKey: true,
                    keyboardKey: keyChar
                ))
            }
        }
        
        return keys
    }
    
    init(audioEngine: AudioEngine? = nil) {
        // Virtual keyboard routes through InstrumentManager
        self.audioEngine = audioEngine
    }
    
    
    /// Configure audio engine reference for tempo-aware latency compensation and transport key forwarding
    func configure(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }
    
    func startListening() {
        // Monitor key down events
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Ignore key repeats (holding down a key) - we want one note per physical press
            if event.isARepeat {
                return nil // Consume the repeat event without triggering another note
            }
            
            // Forward DAW transport keys to AudioEngine.
            // The VK sheet blocks the parent window's keyboard shortcuts,
            // so we handle transport keys here directly.
            // NSEvent local monitors always run on the main thread, so
            // MainActor.assumeIsolated is safe and executes synchronously
            // (avoiding Task delays that could cause race conditions).
            if !event.modifierFlags.contains(.command) && 
               !event.modifierFlags.contains(.control) &&
               !event.modifierFlags.contains(.option) {
                if let char = event.characters?.lowercased().first {
                    switch char {
                    case "r":
                        // Post notification so DAWControlBar handles it with count-in logic.
                        // Previously called audioEngine.record() directly, which bypassed count-in.
                        NotificationCenter.default.post(name: .toggleRecording, object: nil)
                        return nil
                    case "\r":
                        MainActor.assumeIsolated {
                            self.audioEngine?.seek(toBeat: 0)
                        }
                        return nil
                    case ",":
                        MainActor.assumeIsolated {
                            self.audioEngine?.rewindBeats(1)
                        }
                        return nil
                    case ".":
                        MainActor.assumeIsolated {
                            self.audioEngine?.fastForwardBeats(1)
                        }
                        return nil
                    default:
                        break
                    }
                }
            }
            
            // Ignore if modifier keys are pressed (except shift for uppercase)
            if event.modifierFlags.contains(.command) || 
               event.modifierFlags.contains(.control) ||
               event.modifierFlags.contains(.option) {
                return event
            }
            
            if let char = event.characters?.lowercased().first {
                // Use hardware timestamp for precise latency compensation
                if self.handleKeyDown(char, hardwareTimestamp: event.timestamp) {
                    return nil // Consume the event
                }
            }
            return event
        }
        
        // Monitor key up events
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self = self else { return event }
            
            // Transport keys are handled in keyDown — consume keyUp to prevent interference
            if !event.modifierFlags.contains(.command) && 
               !event.modifierFlags.contains(.control) &&
               !event.modifierFlags.contains(.option) {
                if let char = event.characters?.lowercased().first {
                    let transportKeys: Set<Character> = ["r", "\r", ",", "."]
                    if transportKeys.contains(char) {
                        return nil // Consume - already handled in keyDown
                    }
                }
            }
            
            if let char = event.characters?.lowercased().first {
                // Use hardware timestamp for precise latency compensation
                if self.handleKeyUp(char, hardwareTimestamp: event.timestamp) {
                    return nil
                }
            }
            return event
        }
    }
    
    func stopListening() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        
        // Release all notes (both pressed and sustained)
        // No hardware timestamp available during cleanup - use fallback
        for pitch in pressedNotes {
            sendNoteOff(pitch, hardwareTimestamp: nil)
        }
        for pitch in sustainedNotes {
            sendNoteOff(pitch, hardwareTimestamp: nil)
        }
        pressedNotes.removeAll()
        sustainedNotes.removeAll()
    }
    
    private func handleKeyDown(_ char: Character, hardwareTimestamp: TimeInterval? = nil) -> Bool {
        // Check for control keys
        switch char {
        case "z":
            octaveDown()
            return true
        case "x":
            octaveUp()
            return true
        case "c":
            velocityDown()
            return true
        case "v":
            velocityUp()
            return true
        case " ":
            setSustain(!sustainEnabled)
            return true
        default:
            break
        }
        
        // Check for note keys
        if let pitch = pitchForKey(char) {
            // ALWAYS allow noteOn, even if note is currently sustained
            // This enables piano-style retriggering while sustain is active
            noteOn(pitch, hardwareTimestamp: hardwareTimestamp)
            return true
        }
        
        return false
    }
    
    private func handleKeyUp(_ char: Character, hardwareTimestamp: TimeInterval? = nil) -> Bool {
        if let pitch = pitchForKey(char) {
            noteOff(pitch, hardwareTimestamp: hardwareTimestamp)
            return true
        }
        return false
    }
    
    /// Map keyboard character to MIDI pitch (internal for testing)
    internal func pitchForKey(_ char: Character) -> UInt8? {
        let basePitch = UInt8(octave * 12)
        
        // White keys
        if let index = whiteKeyChars.firstIndex(of: char) {
            return basePitch + UInt8(whiteKeyOffsets[index])
        }
        
        // Black keys
        if let index = blackKeyChars.firstIndex(of: char) {
            return basePitch + UInt8(blackKeyOffsets[index])
        }
        
        return nil
    }
    
    // MARK: - Note Routing
    
    /// Send note on - routes to active track instrument with latency compensation
    /// - Parameters:
    ///   - pitch: MIDI pitch to trigger
    ///   - hardwareTimestamp: Optional NSEvent.timestamp for precise latency calculation
    private func sendNoteOn(_ pitch: UInt8, hardwareTimestamp: TimeInterval?) {
        guard instrumentManager.hasActiveInstrument else { return }
        
        // Calculate latency compensation from hardware timestamp or use fallback
        let compensationBeats: Double
        if let hwTimestamp = hardwareTimestamp {
            let actualLatency = calculateActualLatency(hardwareTimestamp: hwTimestamp)
            compensationBeats = latencySecondsToBeats(actualLatency)
        } else {
            // Fallback to fixed compensation for events without hardware timestamp
            compensationBeats = latencySecondsToBeats(fallbackLatencySeconds)
        }
        
        // Apply UI latency compensation for accurate recording timestamps
        instrumentManager.noteOn(pitch: pitch, velocity: velocity, compensationBeats: compensationBeats)
    }
    
    /// Send note off - routes to active track instrument with latency compensation
    /// - Parameters:
    ///   - pitch: MIDI pitch to release
    ///   - hardwareTimestamp: Optional NSEvent.timestamp for precise latency calculation
    private func sendNoteOff(_ pitch: UInt8, hardwareTimestamp: TimeInterval?) {
        guard instrumentManager.hasActiveInstrument else { return }
        
        // Calculate latency compensation from hardware timestamp or use fallback
        let compensationBeats: Double
        if let hwTimestamp = hardwareTimestamp {
            let actualLatency = calculateActualLatency(hardwareTimestamp: hwTimestamp)
            compensationBeats = latencySecondsToBeats(actualLatency)
        } else {
            // Fallback to fixed compensation for events without hardware timestamp
            compensationBeats = latencySecondsToBeats(fallbackLatencySeconds)
        }
        
        // Apply UI latency compensation for accurate recording timestamps
        instrumentManager.noteOff(pitch: pitch, compensationBeats: compensationBeats)
    }
    
    func noteOn(_ pitch: UInt8, hardwareTimestamp: TimeInterval? = nil) {
        // Remove from sustained notes if retriggering a sustained note
        sustainedNotes.remove(pitch)
        
        // If note is already pressed, send noteOff first (retrigger)
        if pressedNotes.contains(pitch) {
            sendNoteOff(pitch, hardwareTimestamp: hardwareTimestamp)
        }
        
        // Add to pressed notes and send noteOn
        pressedNotes.insert(pitch)
        sendNoteOn(pitch, hardwareTimestamp: hardwareTimestamp)
    }
    
    func noteOff(_ pitch: UInt8, hardwareTimestamp: TimeInterval? = nil) {
        // Remove from currently pressed notes
        pressedNotes.remove(pitch)
        
        if sustainEnabled {
            // Sustain is active: add to sustained notes, don't send noteOff yet
            sustainedNotes.insert(pitch)
        } else {
            // No sustain: send noteOff immediately
            sendNoteOff(pitch, hardwareTimestamp: hardwareTimestamp)
        }
    }
    
    func octaveUp() {
        if octave < 8 {
            // Release all notes (pressed and sustained) before changing octave
            // No hardware timestamp available for octave change - use fallback
            for pitch in pressedNotes {
                sendNoteOff(pitch, hardwareTimestamp: nil)
            }
            for pitch in sustainedNotes {
                sendNoteOff(pitch, hardwareTimestamp: nil)
            }
            pressedNotes.removeAll()
            sustainedNotes.removeAll()
            octave += 1
        }
    }
    
    func octaveDown() {
        if octave > 0 {
            // Release all notes (pressed and sustained) before changing octave
            // No hardware timestamp available for octave change - use fallback
            for pitch in pressedNotes {
                sendNoteOff(pitch, hardwareTimestamp: nil)
            }
            for pitch in sustainedNotes {
                sendNoteOff(pitch, hardwareTimestamp: nil)
            }
            pressedNotes.removeAll()
            sustainedNotes.removeAll()
            octave -= 1
        }
    }
    
    func velocityUp() {
        velocity = min(127, velocity + 16)
    }
    
    func velocityDown() {
        velocity = max(1, velocity - 16)
    }
    
    func setSustain(_ enabled: Bool) {
        let wasEnabled = sustainEnabled
        sustainEnabled = enabled
        
        // Also update InstrumentManager's sustain state
        instrumentManager.isSustainActive = enabled
        
        // When sustain is released, send noteOff for all sustained notes
        // (but NOT for currently pressed notes - they should keep playing)
        if wasEnabled && !enabled {
            for pitch in sustainedNotes {
                // Only send noteOff if key is not currently pressed
                if !pressedNotes.contains(pitch) {
                    // No hardware timestamp available for sustain release - use fallback
                    sendNoteOff(pitch, hardwareTimestamp: nil)
                }
            }
            sustainedNotes.removeAll()
        }
    }
    
    // MARK: - Cleanup
}

// MARK: - Notification

extension Notification.Name {
    static let toggleVirtualKeyboard = Notification.Name("toggleVirtualKeyboard")
    static let togglePianoRoll = Notification.Name("togglePianoRoll")
    static let toggleSynthesizer = Notification.Name("toggleSynthesizer")
    static let revealBeatInTimeline = Notification.Name("revealBeatInTimeline")
    static let toggleRecording = Notification.Name("toggleRecording")
}

