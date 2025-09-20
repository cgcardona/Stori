//
//  DAWControlBar.swift
//  TellUrStoriDAW
//
//  Professional DAW control bar with industry-standard layout and functionality
//

import SwiftUI

struct DAWControlBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var showingMixer: Bool
    @Binding var showingLibrary: Bool
    @Binding var showingInspector: Bool
    
    // MARK: - State
    @State private var showingTempoEditor = false
    @State private var showingKeySignatureEditor = false
    @State private var showingTimeSignatureEditor = false
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Section: View Toggles
            HStack(spacing: 6) {
                DAWControlButton(
                    icon: "slider.horizontal.3",
                    isActive: showingMixer,
                    tooltip: "Show/Hide Mixer (⌘M)"
                ) {
                    showingMixer.toggle()
                }
                .keyboardShortcut("m", modifiers: .command)
                
                DAWControlButton(
                    icon: "books.vertical",
                    isActive: showingLibrary,
                    tooltip: "Show/Hide Library (⌘L)"
                ) {
                    showingLibrary.toggle()
                }
                .keyboardShortcut("l", modifiers: .command)
                
                DAWControlButton(
                    icon: "sidebar.right",
                    isActive: showingInspector,
                    tooltip: "Show/Hide Inspector (⌘I)"
                ) {
                    showingInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            .padding(.leading, 12)
            
            Spacer()
            
            // MARK: - Center Section: Transport Controls & Info
            HStack(spacing: 8) {
                // Transport Controls
                HStack(spacing: 2) {
                    // Go to Beginning
                    TransportButton(
                        icon: "backward.end.fill",
                        isActive: false,
                        action: { audioEngine.seek(to: 0) }
                    )
                    .help("Go to Beginning (Home)")
                    .keyboardShortcut(.home, modifiers: [])
                    
                    // Rewind
                    TransportButton(
                        icon: "backward.fill",
                        isActive: false,
                        action: { 
                            let currentTime = audioEngine.currentPosition.timeInterval
                            audioEngine.seek(to: max(0, currentTime - 10))
                        }
                    )
                    .help("Rewind 10 seconds (←)")
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    
                    // Play/Pause
                    TransportButton(
                        icon: audioEngine.isPlaying ? "pause.fill" : "play.fill",
                        isActive: audioEngine.isPlaying,
                        action: {
                            if audioEngine.isPlaying {
                                audioEngine.stop()
                            } else {
                                audioEngine.play()
                            }
                        }
                    )
                    .help(audioEngine.isPlaying ? "Pause (Space)" : "Play (Space)")
                    .keyboardShortcut(.space, modifiers: [])
                    
                    // Stop
                    TransportButton(
                        icon: "stop.fill",
                        isActive: false,
                        action: { 
                            audioEngine.stop()
                            audioEngine.seek(to: 0)
                        }
                    )
                    .help("Stop (⌘Space)")
                    .keyboardShortcut(.space, modifiers: .command)
                    
                    // Record
                    TransportButton(
                        icon: "record.circle.fill",
                        isActive: audioEngine.isRecording,
                        action: {
                            if audioEngine.isRecording {
                                audioEngine.stopRecording()
                            } else {
                                audioEngine.record()
                            }
                        }
                    )
                    .help(audioEngine.isRecording ? "Stop Recording (R)" : "Record (R)")
                    .keyboardShortcut("r", modifiers: [])
                    
                    // Fast Forward
                    TransportButton(
                        icon: "forward.fill",
                        isActive: false,
                        action: { 
                            let currentTime = audioEngine.currentPosition.timeInterval
                            audioEngine.seek(to: currentTime + 10)
                        }
                    )
                    .help("Fast Forward 10 seconds (→)")
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    
                    // Go to End
                    TransportButton(
                        icon: "forward.end.fill",
                        isActive: false,
                        action: { 
                            if let project = projectManager.currentProject {
                                let duration = project.tracks.compactMap { track in
                                    track.regions.map { $0.startTime + $0.duration }.max()
                                }.max() ?? 0
                                audioEngine.seek(to: duration)
                            }
                        }
                    )
                    .help("Go to End (End)")
                    .keyboardShortcut(.end, modifiers: [])
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Cycle
                TransportButton(
                    icon: "repeat",
                    isActive: audioEngine.isCycleEnabled,
                    action: { audioEngine.toggleCycle() }
                )
                .help("Toggle Cycle Mode (C)")
                .keyboardShortcut("c", modifiers: [])
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Time Display
                VStack(spacing: 1) {
                    Text(audioEngine.currentTimeString)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("BARS \(audioEngine.currentMusicalTimeString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 8)
                
                // Project Info
                HStack(spacing: 8) {
                    // Tempo
                    Button(action: { showingTempoEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text("\(Int(projectManager.currentProject?.tempo ?? 120))")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("BPM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Edit Tempo (⌘T)")
                    .keyboardShortcut("t", modifiers: .command)
                    .contextMenu {
                        Button("Set to 60 BPM") { setTempo(60) }
                        Button("Set to 120 BPM") { setTempo(120) }
                        Button("Set to 140 BPM") { setTempo(140) }
                        Button("Set to 180 BPM") { setTempo(180) }
                        Divider()
                        Button("Tap Tempo") { /* TODO: Implement tap tempo */ }
                    }
                    .popover(isPresented: $showingTempoEditor) {
                        tempoEditor
                    }
                    
                    // Key Signature
                    Button(action: { showingKeySignatureEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text(projectManager.currentProject?.keySignature ?? "C")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("KEY")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Edit Key Signature (⌘K)")
                    .keyboardShortcut("k", modifiers: .command)
                    .contextMenu {
                        Button("C Major") { setKeySignature("C") }
                        Button("G Major") { setKeySignature("G") }
                        Button("D Major") { setKeySignature("D") }
                        Button("A Major") { setKeySignature("A") }
                        Button("E Major") { setKeySignature("E") }
                        Divider()
                        Button("F Major") { setKeySignature("F") }
                        Button("Bb Major") { setKeySignature("Bb") }
                        Button("Eb Major") { setKeySignature("Eb") }
                    }
                    .popover(isPresented: $showingKeySignatureEditor) {
                        keySignatureEditor
                    }
                    
                    // Time Signature
                    Button(action: { showingTimeSignatureEditor.toggle() }) {
                        VStack(spacing: 1) {
                            Text(projectManager.currentProject?.timeSignature.description ?? "4/4")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                            Text("TIME")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Edit Time Signature (⌘⇧T)")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .contextMenu {
                        Button("4/4") { setTimeSignature(4, 4) }
                        Button("3/4") { setTimeSignature(3, 4) }
                        Button("2/4") { setTimeSignature(2, 4) }
                        Button("6/8") { setTimeSignature(6, 8) }
                        Button("12/8") { setTimeSignature(12, 8) }
                        Divider()
                        Button("7/8") { setTimeSignature(7, 8) }
                        Button("5/4") { setTimeSignature(5, 4) }
                    }
                    .popover(isPresented: $showingTimeSignatureEditor) {
                        timeSignatureEditor
                    }
                }
            }
            
            Spacer()
            
            // MARK: - Right Section: Master Volume & View Controls
            HStack(spacing: 8) {
                // Master Volume
                VStack(spacing: 2) {
                    Text("MASTER")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: Binding(
                            get: { audioEngine.masterVolume },
                            set: { newValue in
                                audioEngine.updateMasterVolume(Float(newValue))
                            }
                        ), in: 0...1)
                            .frame(width: 60)
                            .help("Master Volume: \(Int(audioEngine.masterVolume * 100))%")
                        
                        Text("\(Int(audioEngine.masterVolume * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 28)
                    }
                }
                .help("Master Volume Control")
                
                // Separator
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 1, height: 32)
                    .padding(.horizontal, 6)
                
                
                // More View Toggles
                HStack(spacing: 6) {
                    DAWControlButton(
                        icon: "waveform",
                        isActive: false,
                        tooltip: "Show/Hide Track Area (⌘⇧T)"
                    ) {
                        // TODO: Toggle track area visibility
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    
                    DAWControlButton(
                        icon: "list.bullet",
                        isActive: false,
                        tooltip: "Show/Hide Event List (⌘E)"
                    ) {
                        // TODO: Toggle event list visibility
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    
                    DAWControlButton(
                        icon: "square.grid.3x3",
                        isActive: false,
                        tooltip: "Show/Hide Step Sequencer (⌘⇧S)"
                    ) {
                        // TODO: Toggle step sequencer visibility
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 56)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    
    // MARK: - Helper Methods
    private func setTempo(_ tempo: Double) {
        projectManager.updateTempo(tempo)
    }
    
    private func setKeySignature(_ keySignature: String) {
        projectManager.updateKeySignature(keySignature)
    }
    
    private func setTimeSignature(_ numerator: Int, _ denominator: Int) {
        let timeSignature = TimeSignature(numerator: numerator, denominator: denominator)
        projectManager.updateTimeSignature(timeSignature)
    }
    
    // MARK: - Editor Views
    private var tempoEditor: some View {
        VStack(spacing: 12) {
            Text("Tempo")
                .font(.headline)
            
            HStack {
                TextField("BPM", value: .constant(projectManager.currentProject?.tempo ?? 120), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                Text("BPM")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Cancel") { showingTempoEditor = false }
                Button("OK") { showingTempoEditor = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 200)
    }
    
    private var keySignatureEditor: some View {
        VStack(spacing: 12) {
            Text("Key Signature")
                .font(.headline)
            
            // Key signature picker would go here
            Text("Key signature editor coming soon")
                .foregroundColor(.secondary)
            
            Button("OK") { showingKeySignatureEditor = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 200)
    }
    
    private var timeSignatureEditor: some View {
        VStack(spacing: 12) {
            Text("Time Signature")
                .font(.headline)
            
            // Time signature picker would go here
            Text("Time signature editor coming soon")
                .foregroundColor(.secondary)
            
            Button("OK") { showingTimeSignatureEditor = false }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 200)
    }
}

#Preview {
    DAWControlBar(
        audioEngine: AudioEngine(),
        projectManager: ProjectManager(),
        showingMixer: .constant(false),
        showingLibrary: .constant(false),
        showingInspector: .constant(false)
    )
    .frame(width: 800)
}
